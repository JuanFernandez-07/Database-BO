-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ REEMPLAZADO EN PARTE POR "Produccion V2" (29/10/2026: resumen por bloques, job único).
--   NO volver a ejecutar después de Produccion V2/02: regresa vta.vw_rvd_gndsale_neto a la
--   categoría por TYPEID y vuelve a crear SPs que borran el día completo del resumen.
-- ════════════════════════════════════════════════════════════════════════════════════
-- PRODUCCIÓN · Paso 1 de 5 · Base: sm_backoffice
-- Ranking de Ventas — crea TODO lo de base de datos en un solo script (estado final).
-- Reemplaza en producción a los scripts de desarrollo 001, 004, 005 y 006: NO correr esos.
-- Requiere antes 05_sm_pos_Propina_FiscalInvoice.sql (columna FiscalInvoice.Propina y su trigger).
-- Es idempotente: si se vuelve a ejecutar, no duplica tablas, tipo ni filas de control.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Fuentes (mismo servidor, base sm_pos):
--   * GT / SV: sm_pos.dbo.FiscalInvoice
--       LC_UNIT = tienda, LC_DOB = fecha, DocTypeId 1 = venta (+) / 10 = reembolso (-),
--       venta del ranking = TaxableAmount (sin IVA). La propina (FiscalInvoice.Propina) viene dentro
--       de TaxableAmount, TotalTax y TotalTxn: se quita la parte proporcional de cada uno y se guarda
--       aparte en rvd_propina.
--       Categoría por TermId: 1-5 Panadería, 6-15 Restaurante, resto -> Otros.
--   * USA: sm_pos.dbo.RankingGNDSALE (formato Aloha)
--       LC_UNIT = tienda, LC_DOB = fecha, venta = AMOUNT de TYPE 52 (sin impuesto, ya neta).
--       Categoría por TYPEID: 603 Restaurante y 1 Alimentos -> Restaurante, 2 -> Panadería,
--       resto -> Otros. TYPEID 74 (Propina) se excluye.
--   * Ninguna tienda debe estar en ambas fuentes (se sumaría dos veces).
--
-- Proceso incremental (lo ejecuta el job cada 15 min):
--   FechaImportacion solo DETECTA qué (tienda, día) cambiaron; esos días se RECALCULAN completos.
--   Una marca de agua por fuente (los importadores son independientes). Se usa >= la última
--   marca para volver a revisar siempre el último lote. Marca en DATETIME (mismo tipo que el
--   origen: comparar datetime contra datetime2 falla en milisegundos .xx3/.xx7).
--
-- IMPORTANTE: si se cambia un mapeo de categorías en las vistas, el incremental NO reclasifica
-- los días ya procesados: ejecutar vta.rvd_RecalcularResumenRango sobre todo el rango con datos.

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificaciones previas ──────────────────────────────────────────────────────
-- Si alguna falla, SET NOEXEC ON evita que se ejecuten los bloques siguientes (en SSMS un error
-- solo detiene su propio bloque). Al final del script se vuelve a SET NOEXEC OFF.
DECLARE @error NVARCHAR(400) =
    CASE
        WHEN SCHEMA_ID('vta') IS NULL
            THEN N'No existe el esquema vta en sm_backoffice.'
        WHEN NOT EXISTS (SELECT 1 FROM sm_pos.INFORMATION_SCHEMA.COLUMNS
                         WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'FiscalInvoice'
                           AND COLUMN_NAME = 'FechaImportacion' AND DATA_TYPE = 'datetime')
            THEN N'sm_pos.dbo.FiscalInvoice.FechaImportacion no existe o no es DATETIME.'
        WHEN NOT EXISTS (SELECT 1 FROM sm_pos.INFORMATION_SCHEMA.COLUMNS
                         WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'FiscalInvoice'
                           AND COLUMN_NAME = 'Propina')
            THEN N'sm_pos.dbo.FiscalInvoice.Propina no existe.'
        WHEN NOT EXISTS (SELECT 1 FROM sm_pos.INFORMATION_SCHEMA.COLUMNS
                         WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'RankingGNDSALE'
                           AND COLUMN_NAME = 'FechaImportacion' AND DATA_TYPE = 'datetime')
            THEN N'sm_pos.dbo.RankingGNDSALE.FechaImportacion no existe o no es DATETIME.'
    END;

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Vistas de origen ────────────────────────────────────────────────────────────
-- GT / SV
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
    CASE fi.DocTypeId WHEN 10 THEN 1 ELSE 0 END                                AS es_reembolso,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TaxableAmount, 0) * pr.factor AS venta_sin_iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TotalTax, 0) * pr.factor      AS iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END
        * (ISNULL(fi.TotalTxn, 0) - ISNULL(fi.Propina, 0))                      AS venta_con_iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.Propina, 0)        AS propina,
    ISNULL(fi.TaxableAmount, 0) * pr.factor                                     AS monto_sin_iva_documento,
    -- Minutos desde la medianoche (sin segundos): LY hasta la hora actual cuando la fecha es hoy.
    DATEPART(HOUR, fi.SysDate) * 60 + DATEPART(MINUTE, fi.SysDate)              AS minuto_del_dia,
    fi.FechaImportacion
FROM sm_pos.dbo.FiscalInvoice fi
-- Propina (GNDITEM ITEM 999323, la llena trg_FiscalInvoice_Propina): no es venta. Viene dentro de
-- TaxableAmount, TotalTax y TotalTxn (Aloha le cobra IVA), así que se quita la parte proporcional
-- de cada monto y se expone aparte en la columna propina. La proporción sirve con IVA 12% y 13%.
CROSS APPLY (
    SELECT CASE WHEN ISNULL(fi.TotalTxn, 0) = 0 THEN 1
                ELSE (fi.TotalTxn - ISNULL(fi.Propina, 0)) / fi.TotalTxn
           END AS factor
) pr
WHERE fi.DocTypeId IN (1, 10);
GO

-- USA
CREATE OR ALTER VIEW vta.vw_rvd_gndsale_neto
AS
SELECT
    g.LC_UNIT AS tienda,
    g.LC_DOB  AS fecha,
    CASE
        WHEN g.TYPEID IN (603, 1) THEN 'restaurante'
        WHEN g.TYPEID = 2         THEN 'panaderia'
        ELSE 'otros'
    END AS categoria,
    0                         AS es_reembolso,
    -- GNDSALE agrega por check y categoría: no se cuentan documentos (rvd_cantidad_ventas = 0).
    0                         AS cuenta_venta,
    ISNULL(g.AMOUNT, 0)       AS venta_sin_iva,
    CAST(0 AS DECIMAL(18, 2)) AS iva,
    ISNULL(g.AMOUNT, 0)       AS venta_con_iva,
    CAST(0 AS DECIMAL(18, 2)) AS propina,  -- pendiente: la de US está en TYPEID 74 (excluido abajo)
    CAST(0 AS DECIMAL(18, 2)) AS monto_sin_iva_documento,
    -- Minutos desde la medianoche: LY hasta la hora actual cuando la fecha es hoy.
    g.CLOSEHOUR * 60 + g.CLOSEMIN AS minuto_del_dia,
    g.FechaImportacion
FROM sm_pos.dbo.RankingGNDSALE g
WHERE g.TYPE = 52
  AND g.TYPEID <> 74;  -- Propina
GO

-- Unificada (la que usa el recálculo)
CREATE OR ALTER VIEW vta.vw_rvd_venta_neta
AS
SELECT 'fiscal_invoice' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       1 - es_reembolso AS cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, propina, monto_sin_iva_documento, minuto_del_dia, FechaImportacion
FROM vta.vw_rvd_fiscal_invoice_neto
UNION ALL
SELECT 'gndsale' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, propina, monto_sin_iva_documento, minuto_del_dia, FechaImportacion
FROM vta.vw_rvd_gndsale_neto;
GO

-- ─── 2. Tipo tabla y tablas ─────────────────────────────────────────────────────────
IF TYPE_ID('vta.rvd_tienda_dia') IS NULL
    CREATE TYPE vta.rvd_tienda_dia AS TABLE (
        tienda INT  NOT NULL,
        fecha  DATE NOT NULL,
        PRIMARY KEY (tienda, fecha)
    );
GO

IF OBJECT_ID('vta.rvt_rvd_resumen_venta_diaria', 'U') IS NULL
    CREATE TABLE vta.rvt_rvd_resumen_venta_diaria (
        rvd_fecha               DATE           NOT NULL,
        rvd_codigo_tie          INT            NOT NULL,
        rvd_categoria           VARCHAR(20)    NOT NULL,  -- restaurante | panaderia | otros
        rvd_venta_sin_iva       DECIMAL(18, 2) NOT NULL,  -- neto: ventas - reembolsos
        rvd_iva                 DECIMAL(18, 2) NOT NULL,
        rvd_venta_con_iva       DECIMAL(18, 2) NOT NULL,
        rvd_reembolso_sin_iva   DECIMAL(18, 2) NOT NULL,  -- informativo, en positivo
        rvd_cantidad_ventas     INT            NOT NULL,  -- 0 para USA
        rvd_cantidad_reembolsos INT            NOT NULL,
        rvd_actualizado_en      DATETIME2(0)   NOT NULL,
        rvd_propina             DECIMAL(18, 2) NOT NULL
            CONSTRAINT DF_rvt_rvd_resumen_venta_diaria_propina DEFAULT (0),  -- ya descontada de las ventas
        CONSTRAINT PK_rvt_rvd_resumen_venta_diaria PRIMARY KEY (rvd_fecha, rvd_codigo_tie, rvd_categoria)
    );
GO

-- Tabla creada antes de la propina (28/10/2026).
IF COL_LENGTH('vta.rvt_rvd_resumen_venta_diaria', 'rvd_propina') IS NULL
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria
        ADD rvd_propina DECIMAL(18, 2) NOT NULL
            CONSTRAINT DF_rvt_rvd_resumen_venta_diaria_propina DEFAULT (0);
GO

IF OBJECT_ID('vta.rvt_cpr_control_proceso', 'U') IS NULL
    CREATE TABLE vta.rvt_cpr_control_proceso (
        cpr_proceso                  VARCHAR(50)    NOT NULL PRIMARY KEY,
        cpr_ultima_fecha_importacion DATETIME       NULL,  -- mismo tipo que FechaImportacion
        cpr_ultima_ejecucion         DATETIME2(0)   NULL,
        cpr_dias_recalculados        INT            NULL,
        cpr_ultimo_error             NVARCHAR(4000) NULL
    );
GO

-- Fechas especiales (01/11, 24/12…) por negocio. TY = ese día del año en curso, LY = año anterior.
-- Al elegir una, solo aparecen las tiendas de los negocios que la tienen configurada y activa.
IF OBJECT_ID('vta.rvt_fes_fecha_especial', 'U') IS NULL
    CREATE TABLE vta.rvt_fes_fecha_especial (
        fes_codigo_neg INT           NOT NULL,
        fes_mes        TINYINT       NOT NULL,
        fes_dia        TINYINT       NOT NULL,
        fes_nombre     NVARCHAR(100) NOT NULL,
        fes_estado     BIT           NOT NULL CONSTRAINT DF_rvt_fes_fecha_especial_estado DEFAULT (1),
        CONSTRAINT PK_rvt_fes_fecha_especial PRIMARY KEY (fes_codigo_neg, fes_mes, fes_dia),
        CONSTRAINT CK_rvt_fes_fecha_especial_mes CHECK (fes_mes BETWEEN 1 AND 12),
        CONSTRAINT CK_rvt_fes_fecha_especial_dia CHECK (fes_dia BETWEEN 1 AND 31)
    );
GO

-- Fechas iniciales (AJUSTAR negocios y nombres antes de ejecutar). Solo inserta las que no existan.
-- Negocios: 1 SM Guatemala, 2 SM El Salvador, 3 SM USA, 4 Cielito Lindo GT, 5 Cielito Lindo Grill GT.
INSERT INTO vta.rvt_fes_fecha_especial (fes_codigo_neg, fes_mes, fes_dia, fes_nombre)
SELECT v.neg, v.mes, v.dia, v.nombre
FROM (VALUES
    (1, 11,  1, N'Día de Todos los Santos'),
    (1, 12, 24, N'Nochebuena'),
    (1,  1,  6, N'Día de Reyes'),
    (1,  5, 10, N'Día de la Madre'),
    (1,  9, 15, N'Día de la Independencia'),
    (1,  2, 14, N'Día del Cariño'),
    (2, 11,  1, N'Día de Todos los Santos'),
    (2, 12, 24, N'Nochebuena'),
    (2,  1,  6, N'Día de Reyes'),
    (2,  5, 10, N'Día de la Madre'),
    (2,  2, 14, N'Día del Cariño'),
    (3, 11,  1, N'Día de Todos los Santos'),
    (3, 12, 24, N'Nochebuena'),
    (3,  1,  6, N'Día de Reyes'),
    (3,  5, 10, N'Día de la Madre'),
    (3,  2, 14, N'Día del Cariño')
) AS v(neg, mes, dia, nombre)
WHERE NOT EXISTS (
    SELECT 1 FROM vta.rvt_fes_fecha_especial f
    WHERE f.fes_codigo_neg = v.neg AND f.fes_mes = v.mes AND f.fes_dia = v.dia);
GO

-- Una fila (marca de agua) por fuente.
INSERT INTO vta.rvt_cpr_control_proceso (cpr_proceso)
SELECT v.proceso
FROM (VALUES ('resumen_venta_diaria'), ('resumen_venta_diaria_us')) AS v(proceso)
WHERE NOT EXISTS (SELECT 1 FROM vta.rvt_cpr_control_proceso c WHERE c.cpr_proceso = v.proceso);
GO

-- ─── 3. SPs ─────────────────────────────────────────────────────────────────────────
-- Fecha desde la que GT/SV se cargan directo desde KIO (vta.rvd_ImportarVentaDesdeKIO, script 07).
-- Desde esa fecha, el proceso de FiscalInvoice ya no toca GT/SV (solo USA). 9999-12-31 = sin corte.
-- La fija el script 07 al activarse; aquí solo se crea si no existe para no pisarla.
IF OBJECT_ID('vta.rvd_FechaCorteKIO', 'IF') IS NULL
    EXEC (N'CREATE FUNCTION vta.rvd_FechaCorteKIO () RETURNS TABLE AS
           RETURN SELECT CAST(''9999-12-31'' AS DATE) AS fecha_corte;');
GO

-- Interno: recalcula completos los (tienda, día) recibidos. Borra e inserta para que también
-- desaparezcan categorías que ya no tienen ventas ese día. Desde la fecha de corte KIO, ignora
-- las tiendas GT/SV (las escribe vta.rvd_ImportarVentaDesdeKIO).
CREATE OR ALTER PROCEDURE vta.rvd_RecalcularDias
    @dias vta.rvd_tienda_dia READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @a_recalcular vta.rvd_tienda_dia;

    INSERT INTO @a_recalcular (tienda, fecha)
    SELECT d.tienda, d.fecha
    FROM @dias d
    CROSS JOIN vta.rvd_FechaCorteKIO() c
    WHERE d.fecha < c.fecha_corte
       OR EXISTS (SELECT 1 FROM vta.tie_tienda t
                  WHERE t.tie_codigo = d.tienda AND t.tie_codigo_neg = 3);  -- USA

    DELETE r
    FROM vta.rvt_rvd_resumen_venta_diaria r
    JOIN @a_recalcular d
        ON d.tienda = r.rvd_codigo_tie
       AND d.fecha  = r.rvd_fecha;

    INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
        rvd_fecha, rvd_codigo_tie, rvd_categoria,
        rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
        rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en, rvd_propina)
    SELECT
        v.fecha,
        v.tienda,
        v.categoria,
        SUM(v.venta_sin_iva),
        SUM(v.iva),
        SUM(v.venta_con_iva),
        SUM(CASE WHEN v.es_reembolso = 1 THEN v.monto_sin_iva_documento ELSE 0 END),
        SUM(v.cuenta_venta),
        SUM(v.es_reembolso),
        SYSDATETIME(),
        SUM(v.propina)
    FROM vta.vw_rvd_venta_neta v
    JOIN @a_recalcular d
        ON d.tienda = v.tienda
       AND d.fecha  = v.fecha
    GROUP BY v.fecha, v.tienda, v.categoria;
END;
GO

-- Incremental: lo ejecuta el job cada 15 min. Con las marcas en NULL procesa toda la historia.
CREATE OR ALTER PROCEDURE vta.rvd_ActualizarResumenIncremental
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lock INT;
    EXEC @lock = sp_getapplock
        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
        @LockOwner = N'Session', @LockTimeout = 0;
    IF @lock < 0 RETURN;  -- ya hay otra ejecución en curso

    BEGIN TRY
        DECLARE @desde_fi DATETIME = ISNULL(
            (SELECT cpr_ultima_fecha_importacion FROM vta.rvt_cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria'),
            '19000101');
        DECLARE @desde_us DATETIME = ISNULL(
            (SELECT cpr_ultima_fecha_importacion FROM vta.rvt_cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria_us'),
            '19000101');

        DECLARE @hasta_fi DATETIME = (
            SELECT MAX(FechaImportacion) FROM sm_pos.dbo.FiscalInvoice WHERE FechaImportacion >= @desde_fi);
        DECLARE @hasta_us DATETIME = (
            SELECT MAX(FechaImportacion) FROM sm_pos.dbo.RankingGNDSALE WHERE FechaImportacion >= @desde_us);

        -- Si una fuente no tiene nada nuevo, su @hasta es NULL y su parte no aporta días.
        DECLARE @dias vta.rvd_tienda_dia;

        INSERT INTO @dias (tienda, fecha)
        SELECT tienda, fecha
        FROM vta.vw_rvd_fiscal_invoice_neto
        WHERE FechaImportacion >= @desde_fi AND FechaImportacion <= @hasta_fi
        UNION
        SELECT tienda, fecha
        FROM vta.vw_rvd_gndsale_neto
        WHERE FechaImportacion >= @desde_us AND FechaImportacion <= @hasta_us;

        DECLARE @cantidad_dias INT = (SELECT COUNT(*) FROM @dias);

        BEGIN TRAN;
            IF @cantidad_dias > 0
                EXEC vta.rvd_RecalcularDias @dias = @dias;

            UPDATE vta.rvt_cpr_control_proceso
            SET cpr_ultima_fecha_importacion = CASE cpr_proceso
                    WHEN 'resumen_venta_diaria'    THEN ISNULL(@hasta_fi, cpr_ultima_fecha_importacion)
                    WHEN 'resumen_venta_diaria_us' THEN ISNULL(@hasta_us, cpr_ultima_fecha_importacion)
                END,
                cpr_ultima_ejecucion  = SYSDATETIME(),
                cpr_dias_recalculados = @cantidad_dias,
                cpr_ultimo_error      = NULL
            WHERE cpr_proceso IN ('resumen_venta_diaria', 'resumen_venta_diaria_us');
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        UPDATE vta.rvt_cpr_control_proceso
        SET cpr_ultima_ejecucion = SYSDATETIME(),
            cpr_ultimo_error     = ERROR_MESSAGE()
        WHERE cpr_proceso IN ('resumen_venta_diaria', 'resumen_venta_diaria_us');

        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- Recalcula un rango completo (job diario de los últimos 7 días, o reproceso manual).
-- No mueve las marcas de agua.
CREATE OR ALTER PROCEDURE vta.rvd_RecalcularResumenRango
    @fecha_ini DATE,
    @fecha_fin DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @lock INT;
    EXEC @lock = sp_getapplock
        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
        @LockOwner = N'Session', @LockTimeout = 60000;  -- espera hasta 1 min si corre el incremental
    IF @lock < 0 THROW 50001, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

    BEGIN TRY
        DECLARE @dias vta.rvd_tienda_dia;

        INSERT INTO @dias (tienda, fecha)
        SELECT tienda, fecha
        FROM vta.vw_rvd_venta_neta
        WHERE fecha BETWEEN @fecha_ini AND @fecha_fin
        UNION
        SELECT rvd_codigo_tie, rvd_fecha
        FROM vta.rvt_rvd_resumen_venta_diaria
        WHERE rvd_fecha BETWEEN @fecha_ini AND @fecha_fin;

        BEGIN TRAN;
            EXEC vta.rvd_RecalcularDias @dias = @dias;
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- Completa sm_pos.dbo.FiscalInvoice.Propina de las facturas que quedaron en NULL porque su check aún
-- no estaba en ALOHA.dbo.GNDITEM al importarse (ver 05_sm_pos_Propina_FiscalInvoice.sql) y
-- recalcula en el resumen solo esos (tienda, día): llenar la propina no mueve FechaImportacion, así
-- que el incremental no se entera. Jobs (paso 3): cada 15 min con @dias_atras = 1 (hoy y ayer) y a las
-- 02:00 con 7. Lo que siga en NULL fuera de esa ventana ya no se busca y cuenta como propina 0.
CREATE OR ALTER PROCEDURE vta.rvd_CompletarPropinaPendiente
    @dias_atras INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @desde DATE = DATEADD(DAY, -@dias_atras, CAST(GETDATE() AS DATE));

    SELECT fi.StoreFiscalId, fi.GUID, fi.LC_UNIT, fi.LC_DOB, fi.CheckNumber
    INTO #pendientes
    FROM sm_pos.dbo.FiscalInvoice fi
    WHERE fi.LC_DOB >= @desde
      AND fi.Propina IS NULL
      AND fi.DocTypeId IN (1, 10);

    IF NOT EXISTS (SELECT 1 FROM #pendientes) RETURN;

    -- Solo los checks que ya están en GNDITEM: 0 si no tienen línea de propina (ITEM 999323).
    SELECT g.LC_UNIT, g.LC_DOB, g.[CHECK],
           SUM(CASE WHEN g.ITEM = 999323 THEN g.DISCPRIC ELSE 0 END) AS Propina
    INTO #gnditem
    FROM ALOHA.dbo.GNDITEM g
    WHERE g.LC_DOB >= @desde
      AND EXISTS (SELECT 1 FROM #pendientes p
                  WHERE p.LC_UNIT = g.LC_UNIT AND p.LC_DOB = g.LC_DOB AND p.CheckNumber = g.[CHECK])
    GROUP BY g.LC_UNIT, g.LC_DOB, g.[CHECK];

    IF NOT EXISTS (SELECT 1 FROM #gnditem) RETURN;

    DECLARE @lock INT;
    EXEC @lock = sp_getapplock
        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
        @LockOwner = N'Session', @LockTimeout = 60000;
    IF @lock < 0 RETURN;  -- las facturas siguen en NULL: las toma la siguiente ejecución

    BEGIN TRY
        CREATE TABLE #actualizadas (LC_UNIT INT NOT NULL, LC_DOB DATE NOT NULL);
        DECLARE @dias vta.rvd_tienda_dia;

        BEGIN TRAN;
            UPDATE fi
            SET fi.Propina = g.Propina
            OUTPUT CONVERT(INT, inserted.LC_UNIT), CONVERT(DATE, inserted.LC_DOB) INTO #actualizadas
            FROM sm_pos.dbo.FiscalInvoice fi
            JOIN #pendientes p
              ON p.StoreFiscalId = fi.StoreFiscalId
             AND p.GUID = fi.GUID
            JOIN #gnditem g
              ON g.LC_UNIT = p.LC_UNIT
             AND g.LC_DOB = p.LC_DOB
             AND g.[CHECK] = p.CheckNumber
            WHERE fi.Propina IS NULL;

            INSERT INTO @dias (tienda, fecha)
            SELECT DISTINCT LC_UNIT, LC_DOB FROM #actualizadas;

            IF EXISTS (SELECT 1 FROM @dias)
                EXEC vta.rvd_RecalcularDias @dias = @dias;
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_releaseapplock @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- ─── 4. Carga inicial ───────────────────────────────────────────────────────────────
-- Con las marcas en NULL, procesa toda la historia de ambas fuentes.
EXEC vta.rvd_ActualizarResumenIncremental;
GO

-- ─── 5. Verificación (pegar resultados) ─────────────────────────────────────────────
-- 5.1 Marcas al día y sin error: cpr_ultima_fecha_importacion = ultima_en_origen.
SELECT c.cpr_proceso, c.cpr_ultima_fecha_importacion, c.cpr_ultima_ejecucion, c.cpr_dias_recalculados, c.cpr_ultimo_error,
       CASE c.cpr_proceso
           WHEN 'resumen_venta_diaria'    THEN (SELECT MAX(FechaImportacion) FROM sm_pos.dbo.FiscalInvoice)
           WHEN 'resumen_venta_diaria_us' THEN (SELECT MAX(FechaImportacion) FROM sm_pos.dbo.RankingGNDSALE)
       END AS ultima_en_origen
FROM vta.rvt_cpr_control_proceso c;

-- 5.2 GT/SV: ambas filas iguales (venta sin IVA ya sin la parte proporcional de la propina).
SELECT 'resumen' AS fuente, SUM(rvd_venta_sin_iva) AS venta_sin_iva, SUM(rvd_propina) AS propina,
       SUM(rvd_cantidad_ventas) AS ventas, SUM(rvd_cantidad_reembolsos) AS reembolsos
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_codigo_tie NOT IN (SELECT DISTINCT LC_UNIT FROM sm_pos.dbo.RankingGNDSALE)
UNION ALL
SELECT 'FiscalInvoice',
       SUM(CASE DocTypeId WHEN 10 THEN -1 ELSE 1 END * TaxableAmount
           * CASE WHEN ISNULL(TotalTxn, 0) = 0 THEN 1 ELSE (TotalTxn - ISNULL(Propina, 0)) / TotalTxn END),
       SUM(CASE DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(Propina, 0)),
       SUM(CASE DocTypeId WHEN 1 THEN 1 ELSE 0 END),
       SUM(CASE DocTypeId WHEN 10 THEN 1 ELSE 0 END)
FROM sm_pos.dbo.FiscalInvoice
WHERE DocTypeId IN (1, 10);

-- 5.3 USA: por tienda, ambas filas iguales.
SELECT 'resumen' AS fuente, rvd_codigo_tie AS tienda, SUM(rvd_venta_sin_iva) AS venta_sin_iva
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_codigo_tie IN (SELECT DISTINCT LC_UNIT FROM sm_pos.dbo.RankingGNDSALE)
GROUP BY rvd_codigo_tie
UNION ALL
SELECT 'RankingGNDSALE', LC_UNIT, SUM(AMOUNT)
FROM sm_pos.dbo.RankingGNDSALE
WHERE TYPE = 52 AND TYPEID <> 74
GROUP BY LC_UNIT
ORDER BY tienda, fuente;

-- 5.4 Tiendas del resumen que NO se verán en pantalla (no existen activas en vta.tie_tienda,
--     o el código se repite entre negocios). Debe devolver 0 filas.
SELECT r.rvd_codigo_tie, COUNT(DISTINCT t.tie_codigo_neg) AS negocios, SUM(r.rvd_venta_sin_iva) AS venta_sin_iva
FROM vta.rvt_rvd_resumen_venta_diaria r
LEFT JOIN vta.tie_tienda t ON t.tie_codigo = r.rvd_codigo_tie AND t.tie_estado = 1
GROUP BY r.rvd_codigo_tie
HAVING COUNT(DISTINCT t.tie_codigo_neg) <> 1;
GO

SET NOEXEC OFF;
GO
