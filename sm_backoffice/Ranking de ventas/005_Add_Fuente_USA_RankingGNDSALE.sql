-- Ejecutar en la base sm_backoffice (después de 001 y 004).

USE sm_backoffice;
GO
-- Agrega las tiendas de USA al resumen del Ranking de Ventas. Su venta no está en
-- sm_pos.dbo.FiscalInvoice sino en sm_pos.dbo.RankingGNDSALE (formato de exportación de Aloha).
--
-- Reglas (2026-10-16):
--   * LC_UNIT = tienda (1001, 1002 = negocio 3, USA), LC_DOB = fecha de negocio.
--   * Venta = AMOUNT de TYPE 52: venta neta sin impuesto por categoría (mismo criterio validado
--     para Aloha en Resumen de Ventas). No viene TYPE 54 (impuesto) → iva = 0.
--   * GNDSALE ya trae la venta neta: no hay documento de reembolso aparte.
--   * Categoría = TYPEID (NO la terminal). Mapeo en vta.vw_rvd_gndsale_neto. TYPEID 74 (Propina)
--     no es venta y se excluye.
--
-- Diseño:
--   * Misma tabla resumen (vta.rvd_resumen_venta_diaria): backend y frontend no cambian.
--   * Vista unificada vta.vw_rvd_venta_neta = FiscalInvoice (GT/SV) UNION ALL RankingGNDSALE (US).
--   * Una marca de agua POR FUENTE en vta.cpr_control_proceso: los importadores son
--     independientes y un lote de una fuente puede terminar de entrar después de que ya se
--     procesó un lote más nuevo de la otra.
--   * Supone que ninguna tienda está en ambas fuentes (verificado 2026-10-16); si lo estuviera,
--     su venta se sumaría dos veces.

-- ─── 1. Vista de USA sobre RankingGNDSALE ───────────────────────────────────────────
CREATE OR ALTER VIEW vta.vw_rvd_gndsale_neto
AS
SELECT
    g.LC_UNIT AS tienda,
    g.LC_DOB  AS fecha,
    -- Categorías de Aloha (definido por negocio 2026-10-16):
    --   603 Restaurante y 1 Alimentos -> Restaurante, 2 Panadería -> Panadería,
    --   cualquier otro TYPEID -> Otros. 74 Propina se excluye en el WHERE: no es venta.
    CASE
        WHEN g.TYPEID IN (603, 1) THEN 'restaurante'
        WHEN g.TYPEID = 2         THEN 'panaderia'
        ELSE 'otros'
    END AS categoria,
    0                     AS es_reembolso,
    -- GNDSALE agrega por check y categoría: la cantidad de documentos no es comparable con
    -- FiscalInvoice, por eso no se cuenta (rvd_cantidad_ventas queda en 0 para USA).
    0                     AS cuenta_venta,
    ISNULL(g.AMOUNT, 0)   AS venta_sin_iva,
    CAST(0 AS DECIMAL(18, 2)) AS iva,
    ISNULL(g.AMOUNT, 0)   AS venta_con_iva,
    CAST(0 AS DECIMAL(18, 2)) AS monto_sin_iva_documento,
    g.FechaImportacion
FROM sm_pos.dbo.RankingGNDSALE g
WHERE g.TYPE = 52
  AND g.TYPEID <> 74;  -- Propina
GO

-- ─── 2. Vista unificada (la que usa el recálculo) ───────────────────────────────────
CREATE OR ALTER VIEW vta.vw_rvd_venta_neta
AS
SELECT 'fiscal_invoice' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       1 - es_reembolso AS cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, monto_sin_iva_documento, FechaImportacion
FROM vta.vw_rvd_fiscal_invoice_neto
UNION ALL
SELECT 'gndsale' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, monto_sin_iva_documento, FechaImportacion
FROM vta.vw_rvd_gndsale_neto;
GO

-- ─── 3. Marca de agua de la fuente USA ──────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM vta.cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria_us')
    INSERT INTO vta.cpr_control_proceso (cpr_proceso) VALUES ('resumen_venta_diaria_us');
GO

-- ─── 4. Recalcular días: ahora sobre la vista unificada ─────────────────────────────
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
        SUM(v.cuenta_venta),
        SUM(v.es_reembolso),
        SYSDATETIME()
    FROM vta.vw_rvd_venta_neta v
    JOIN @dias d
        ON d.tienda = v.tienda
       AND d.fecha  = v.fecha
    GROUP BY v.fecha, v.tienda, v.categoria;
END;
GO

-- ─── 5. Incremental con una marca de agua por fuente ───────────────────────────────
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
        -- DATETIME: mismo tipo que FechaImportacion en ambas fuentes (ver 004).
        DECLARE @desde_fi DATETIME = ISNULL(
            (SELECT cpr_ultima_fecha_importacion FROM vta.cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria'),
            '19000101');
        DECLARE @desde_us DATETIME = ISNULL(
            (SELECT cpr_ultima_fecha_importacion FROM vta.cpr_control_proceso WHERE cpr_proceso = 'resumen_venta_diaria_us'),
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

            UPDATE vta.cpr_control_proceso
            SET cpr_ultima_fecha_importacion = CASE cpr_proceso
                    WHEN 'resumen_venta_diaria'    THEN ISNULL(@hasta_fi, cpr_ultima_fecha_importacion)
                    WHEN 'resumen_venta_diaria_us' THEN ISNULL(@hasta_us, cpr_ultima_fecha_importacion)
                END,
                cpr_ultima_ejecucion  = SYSDATETIME(),
                cpr_dias_recalculados = @cantidad_dias,
                cpr_ultimo_error      = NULL
            WHERE cpr_proceso IN ('resumen_venta_diaria', 'resumen_venta_diaria_us');
        COMMIT;

        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        UPDATE vta.cpr_control_proceso
        SET cpr_ultima_ejecucion = SYSDATETIME(),
            cpr_ultimo_error     = ERROR_MESSAGE()
        WHERE cpr_proceso IN ('resumen_venta_diaria', 'resumen_venta_diaria_us');

        EXEC sp_releaseapplock @Resource = N'vta.rvd_resumen_venta_diaria', @LockOwner = N'Session';
        THROW;
    END CATCH;
END;
GO

-- ─── 6. Recalcular rango: ahora sobre la vista unificada ────────────────────────────
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
        FROM vta.vw_rvd_venta_neta
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

-- ─── 7. Carga de USA ────────────────────────────────────────────────────────────────
-- La marca de USA está en NULL: esta ejecución procesa toda la historia de RankingGNDSALE.
EXEC vta.rvd_ActualizarResumenIncremental;
GO

-- ─── 8. Verificación ────────────────────────────────────────────────────────────────
-- Ambas marcas al día y sin error.
SELECT c.cpr_proceso, c.cpr_ultima_fecha_importacion, c.cpr_ultima_ejecucion, c.cpr_dias_recalculados, c.cpr_ultimo_error,
       CASE c.cpr_proceso
           WHEN 'resumen_venta_diaria'    THEN (SELECT MAX(FechaImportacion) FROM sm_pos.dbo.FiscalInvoice)
           WHEN 'resumen_venta_diaria_us' THEN (SELECT MAX(FechaImportacion) FROM sm_pos.dbo.RankingGNDSALE)
       END AS ultima_en_origen
FROM vta.cpr_control_proceso c;

-- USA: el resumen debe cuadrar con RankingGNDSALE TYPE 52, por tienda.
SELECT 'resumen' AS fuente, rvd_codigo_tie AS tienda, SUM(rvd_venta_sin_iva) AS venta_sin_iva
FROM vta.rvd_resumen_venta_diaria
WHERE rvd_codigo_tie IN (SELECT DISTINCT LC_UNIT FROM sm_pos.dbo.RankingGNDSALE)
GROUP BY rvd_codigo_tie
UNION ALL
SELECT 'RankingGNDSALE', LC_UNIT, SUM(AMOUNT)
FROM sm_pos.dbo.RankingGNDSALE
WHERE TYPE = 52 AND TYPEID <> 74
GROUP BY LC_UNIT
ORDER BY tienda, fuente;

-- GT/SV: debe seguir cuadrando con FiscalInvoice (igual que antes de este script).
SELECT 'resumen' AS fuente, SUM(rvd_venta_sin_iva) AS venta_sin_iva, SUM(rvd_cantidad_ventas) AS ventas
FROM vta.rvd_resumen_venta_diaria
WHERE rvd_codigo_tie NOT IN (SELECT DISTINCT LC_UNIT FROM sm_pos.dbo.RankingGNDSALE)
UNION ALL
SELECT 'FiscalInvoice',
       SUM(CASE DocTypeId WHEN 10 THEN -TaxableAmount ELSE TaxableAmount END),
       SUM(CASE DocTypeId WHEN 1 THEN 1 ELSE 0 END)
FROM sm_pos.dbo.FiscalInvoice
WHERE DocTypeId IN (1, 10);

-- USA por categoría (revisar contra el mapeo de TYPEID).
SELECT rvd_codigo_tie AS tienda, rvd_categoria, SUM(rvd_venta_sin_iva) AS venta_sin_iva
FROM vta.rvd_resumen_venta_diaria
WHERE rvd_codigo_tie IN (SELECT DISTINCT LC_UNIT FROM sm_pos.dbo.RankingGNDSALE)
GROUP BY rvd_codigo_tie, rvd_categoria
ORDER BY rvd_codigo_tie, rvd_categoria;
GO
