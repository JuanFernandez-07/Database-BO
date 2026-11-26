-- Ejecutar en la base sm_backoffice (corrige una instalación hecha con la primera versión de 001).

USE sm_backoffice;
GO
--
-- Problema: la marca de agua y las variables del incremental eran DATETIME2(7), pero
-- sm_pos.dbo.FiscalInvoice.FechaImportacion es DATETIME. Desde SQL Server 2016 la comparación
-- datetime vs datetime2 usa la precisión completa del datetime (.663 = 0.66333...), así que
-- "FechaImportacion <= @hasta" fallaba para el lote más reciente cuando sus milisegundos
-- terminan en 3 o 7. Efecto observado (2026-10-14): cpr_dias_recalculados = 0 — el último lote
-- nunca se volvía a revisar. Los lotes nuevos sí se procesaban; los totales no se duplicaban.
--
-- Corrección: usar DATETIME (mismo tipo que el origen) en la marca y en las variables.

-- ─── 0. Verificar que el origen es DATETIME ─────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1
    FROM sm_pos.INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'FiscalInvoice'
      AND COLUMN_NAME = 'FechaImportacion' AND DATA_TYPE = 'datetime')
    THROW 50010, 'FechaImportacion no es DATETIME: revisar antes de aplicar este script.', 1;
GO

-- ─── 1. Marca de agua como DATETIME ─────────────────────────────────────────────────
ALTER TABLE vta.cpr_control_proceso
    ALTER COLUMN cpr_ultima_fecha_importacion DATETIME NULL;
GO

-- ─── 2. Incremental con variables DATETIME ──────────────────────────────────────────
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
        -- DATETIME (mismo tipo que FechaImportacion), ver comentario al inicio del script.
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

-- ─── 3. Procesar lo pendiente y verificar ───────────────────────────────────────────
EXEC vta.rvd_ActualizarResumenIncremental;
GO

-- Debe mostrar la última FechaImportacion del origen y cpr_dias_recalculados > 0.
SELECT c.cpr_ultima_fecha_importacion, c.cpr_ultima_ejecucion, c.cpr_dias_recalculados, c.cpr_ultimo_error,
       (SELECT MAX(FechaImportacion) FROM sm_pos.dbo.FiscalInvoice) AS ultima_en_origen
FROM vta.cpr_control_proceso c;

-- Las dos filas deben ser iguales.
SELECT 'resumen' AS fuente, SUM(rvd_venta_sin_iva) AS venta_sin_iva, SUM(rvd_cantidad_ventas) AS ventas, SUM(rvd_cantidad_reembolsos) AS reembolsos
FROM vta.rvd_resumen_venta_diaria
UNION ALL
SELECT 'FiscalInvoice',
       SUM(CASE DocTypeId WHEN 10 THEN -TaxableAmount ELSE TaxableAmount END),
       SUM(CASE DocTypeId WHEN 1 THEN 1 ELSE 0 END),
       SUM(CASE DocTypeId WHEN 10 THEN 1 ELSE 0 END)
FROM sm_pos.dbo.FiscalInvoice
WHERE DocTypeId IN (1, 10);
GO
