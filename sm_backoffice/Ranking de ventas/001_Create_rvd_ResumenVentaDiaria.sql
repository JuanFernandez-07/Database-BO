-- Ejecutar en la base sm_backoffice

USE sm_backoffice;
GO
-- Ranking de Ventas (smb_react / smb_net): resumen diario de venta por tienda y categoría,
-- calculado de forma incremental a partir de sm_pos.dbo.FiscalInvoice (mismo servidor).
--
-- Reglas confirmadas por negocio (2026-10-14):
--   * LC_UNIT = tienda, LC_DOB = fecha de negocio.
--   * DocTypeId 1 = venta (suma), 10 = reembolso (resta). El reembolso viene con monto positivo.
--   * Venta del ranking = TaxableAmount (sin IVA). Se guardan también IVA y total con IVA.
--   * Categoría por TermId (igual para todas las tiendas): 1-5 Panadería, 6-15 Restaurante.
--     Todo lo demás (30-34 Café, 35-36 Delivery, 37-38 Autoservicio, u otro) -> 'otros'.
--
-- Cómo funciona el incremental:
--   FechaImportacion solo se usa para DETECTAR qué (tienda, día) cambiaron desde la última
--   ejecución; esos días se RECALCULAN completos desde FiscalInvoice. Así el resumen queda
--   correcto aunque el importador (que no es nuestro) reimporte o corrija checks, o el proceso
--   se ejecute dos veces. Se filtra con >= la última FechaImportacion procesada para volver a
--   revisar siempre el último lote (por si el SP corrió mientras ese lote todavía entraba).

-- ─── Vista sobre FiscalInvoice con signo y categoría ────────────────────────────────
CREATE OR ALTER VIEW vta.vw_rvd_fiscal_invoice_neto
AS
SELECT
    CONVERT(INT, fi.LC_UNIT)  AS tienda,
    CONVERT(DATE, fi.LC_DOB)  AS fecha,
    CASE
        WHEN fi.TermId BETWEEN 1  AND 5  THEN 'panaderia'
        WHEN fi.TermId BETWEEN 6  AND 15 THEN 'restaurante'
        ELSE 'otros'  -- Café (30-34), Delivery (35-36), Autoservicio (37-38) y cualquier otro
    END AS categoria,
    CASE fi.DocTypeId WHEN 10 THEN 1 ELSE 0 END                               AS es_reembolso,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TaxableAmount, 0) AS venta_sin_iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TotalTax, 0)      AS iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TotalTxn, 0)      AS venta_con_iva,
    ISNULL(fi.TaxableAmount, 0)                                                AS monto_sin_iva_documento,
    fi.FechaImportacion
FROM sm_pos.dbo.FiscalInvoice fi
WHERE fi.DocTypeId IN (1, 10);
GO

-- ─── Tabla resumen: una fila por día + tienda + categoría ───────────────────────────
CREATE TABLE vta.rvd_resumen_venta_diaria (
    rvd_fecha               DATE           NOT NULL,
    rvd_codigo_tie          INT            NOT NULL,
    rvd_categoria           VARCHAR(20)    NOT NULL,  -- panaderia | restaurante | otros
    rvd_venta_sin_iva       DECIMAL(18, 2) NOT NULL,  -- neto: ventas - reembolsos (TaxableAmount)
    rvd_iva                 DECIMAL(18, 2) NOT NULL,  -- neto (TotalTax)
    rvd_venta_con_iva       DECIMAL(18, 2) NOT NULL,  -- neto (TotalTxn)
    rvd_reembolso_sin_iva   DECIMAL(18, 2) NOT NULL,  -- informativo: total reembolsado, en positivo
    rvd_cantidad_ventas     INT            NOT NULL,
    rvd_cantidad_reembolsos INT            NOT NULL,
    rvd_actualizado_en      DATETIME2(0)   NOT NULL,
    -- fecha primero: la pantalla siempre consulta por rango de fechas.
    CONSTRAINT PK_rvd_resumen_venta_diaria PRIMARY KEY (rvd_fecha, rvd_codigo_tie, rvd_categoria)
);
GO

-- ─── Tabla de control del proceso (marca de agua) ───────────────────────────────────
CREATE TABLE vta.cpr_control_proceso (
    cpr_proceso                  VARCHAR(50)    NOT NULL PRIMARY KEY,
    -- DATETIME, igual que FiscalInvoice.FechaImportacion: comparar datetime contra datetime2
    -- falla en valores .xx3/.xx7 (desde SQL Server 2016 la conversión usa precisión completa).
    cpr_ultima_fecha_importacion DATETIME       NULL,
    cpr_ultima_ejecucion         DATETIME2(0)   NULL,
    cpr_dias_recalculados        INT            NULL,
    cpr_ultimo_error             NVARCHAR(4000) NULL
);
GO

INSERT INTO vta.cpr_control_proceso (cpr_proceso)
VALUES ('resumen_venta_diaria');
GO

-- ─── Tipo tabla: lista de (tienda, día) a recalcular ────────────────────────────────
CREATE TYPE vta.rvd_tienda_dia AS TABLE (
    tienda INT  NOT NULL,
    fecha  DATE NOT NULL,
    PRIMARY KEY (tienda, fecha)
);
GO

-- ─── Recalcula los (tienda, día) recibidos ──────────────────────────────────────────
-- Uso interno: lo llaman los dos SPs de abajo, que arman la lista y manejan la transacción.
-- Borra e inserta (en vez de MERGE) para que también desaparezcan categorías que ya no
-- tienen documentos en ese día.
CREATE OR ALTER PROCEDURE vta.rvd_RecalcularDias
    @dias vta.rvd_tienda_dia READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DELETE r
    FROM vta.rvd_resumen_venta_diaria r
    JOIN @dias d
        ON d.tienda = r.rvd_codigo_tie
       AND d.fecha  = r.rvd_fecha;

    INSERT INTO vta.rvd_resumen_venta_diaria (
        rvd_fecha, rvd_codigo_tie, rvd_categoria,
        rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
        rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en)
    SELECT
        v.fecha,
        v.tienda,
        v.categoria,
        SUM(v.venta_sin_iva),
        SUM(v.iva),
        SUM(v.venta_con_iva),
        SUM(CASE WHEN v.es_reembolso = 1 THEN v.monto_sin_iva_documento ELSE 0 END),
        SUM(1 - v.es_reembolso),
        SUM(v.es_reembolso),
        SYSDATETIME()
    FROM vta.vw_rvd_fiscal_invoice_neto v
    JOIN @dias d
        ON d.tienda = v.tienda
       AND d.fecha  = v.fecha
    GROUP BY v.fecha, v.tienda, v.categoria;
END;
GO

-- ─── Proceso incremental (lo ejecuta el job cada 15 minutos) ────────────────────────
-- La primera ejecución (marca en NULL) procesa toda la historia = carga inicial.
CREATE OR ALTER PROCEDURE vta.rvd_ActualizarResumenIncremental
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lock INT;
    EXEC @lock = sp_getapplock
        @Resource = N'vta.rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
        @LockOwner = N'Session', @LockTimeout = 0;
    IF @lock < 0 RETURN;  -- ya hay otra ejecución en curso

    BEGIN TRY
        -- DATETIME (mismo tipo que FechaImportacion), ver comentario en vta.cpr_control_proceso.
        DECLARE @desde DATETIME = ISNULL(
            (SELECT cpr_ultima_fecha_importacion FROM vta.cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria'),
            '19000101');

        DECLARE @hasta DATETIME = (
            SELECT MAX(FechaImportacion) FROM sm_pos.dbo.FiscalInvoice WHERE FechaImportacion >= @desde);

        DECLARE @dias vta.rvd_tienda_dia;

        IF @hasta IS NOT NULL
            INSERT INTO @dias (tienda, fecha)
            SELECT DISTINCT tienda, fecha
            FROM vta.vw_rvd_fiscal_invoice_neto
            WHERE FechaImportacion >= @desde
              AND FechaImportacion <= @hasta;

        DECLARE @cantidad_dias INT = (SELECT COUNT(*) FROM @dias);

        BEGIN TRAN;
            IF @cantidad_dias > 0
                EXEC vta.rvd_RecalcularDias @dias = @dias;

            UPDATE vta.cpr_control_proceso
            SET cpr_ultima_fecha_importacion = ISNULL(@hasta, cpr_ultima_fecha_importacion),
                cpr_ultima_ejecucion         = SYSDATETIME(),
                cpr_dias_recalculados        = @cantidad_dias,
                cpr_ultimo_error             = NULL
            WHERE cpr_proceso = 'resumen_venta_diaria';
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        UPDATE vta.cpr_control_proceso
        SET cpr_ultima_ejecucion = SYSDATETIME(),
            cpr_ultimo_error     = ERROR_MESSAGE()
        WHERE cpr_proceso = 'resumen_venta_diaria';

        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- ─── Recalcula un rango de fechas completo (red de seguridad / reproceso manual) ────
-- No mueve la marca de agua. Incluye los días que ya están en el resumen aunque ya no
-- tengan documentos en FiscalInvoice, para que esas filas se borren.
CREATE OR ALTER PROCEDURE vta.rvd_RecalcularResumenRango
    @fecha_ini DATE,
    @fecha_fin DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lock INT;
    EXEC @lock = sp_getapplock
        @Resource = N'vta.rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
        @LockOwner = N'Session', @LockTimeout = 60000;  -- espera hasta 1 min si corre el incremental
    IF @lock < 0 THROW 50001, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

    BEGIN TRY
        DECLARE @dias vta.rvd_tienda_dia;

        INSERT INTO @dias (tienda, fecha)
        SELECT tienda, fecha
        FROM vta.vw_rvd_fiscal_invoice_neto
        WHERE fecha BETWEEN @fecha_ini AND @fecha_fin
        UNION
        SELECT rvd_codigo_tie, rvd_fecha
        FROM vta.rvd_resumen_venta_diaria
        WHERE rvd_fecha BETWEEN @fecha_ini AND @fecha_fin;

        BEGIN TRAN;
            EXEC vta.rvd_RecalcularDias @dias = @dias;
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- ─── Carga inicial ──────────────────────────────────────────────────────────────────
-- Con la marca en NULL, la primera ejecución procesa toda la historia de FiscalInvoice.
EXEC vta.rvd_ActualizarResumenIncremental;
GO

-- Verificación: el total del resumen debe cuadrar con FiscalInvoice.
SELECT 'resumen' AS fuente, SUM(rvd_venta_sin_iva) AS venta_sin_iva, SUM(rvd_cantidad_ventas) AS ventas, SUM(rvd_cantidad_reembolsos) AS reembolsos
FROM vta.rvd_resumen_venta_diaria
UNION ALL
SELECT 'FiscalInvoice',
       SUM(CASE DocTypeId WHEN 10 THEN -TaxableAmount ELSE TaxableAmount END),
       SUM(CASE DocTypeId WHEN 1 THEN 1 ELSE 0 END),
       SUM(CASE DocTypeId WHEN 10 THEN 1 ELSE 0 END)
FROM sm_pos.dbo.FiscalInvoice
WHERE DocTypeId IN (1, 10);

SELECT * FROM vta.cpr_control_proceso;
GO
