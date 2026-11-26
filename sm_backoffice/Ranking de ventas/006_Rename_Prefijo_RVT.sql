-- Ejecutar en la base sm_backoffice (después de 005).

USE sm_backoffice;
GO
-- Convención del proyecto: esquema.prefijomódulo_prefijoentidad_nombre (ej. vta.cdc_cca_corte_caja).
-- Las tablas del Ranking de Ventas toman el prefijo de módulo "rvt":
--   vta.rvd_resumen_venta_diaria -> vta.rvt_rvd_resumen_venta_diaria
--   vta.cpr_control_proceso      -> vta.rvt_cpr_control_proceso
-- sp_rename NO actualiza el texto de los SPs que usan las tablas, por eso se recrean aquí.
-- Las vistas no cambian (leen sm_pos, no estas tablas). Los jobs llaman a los SPs por su nombre,
-- que no cambia. Si el job corre justo entre el rename y la recreación de los SPs, fallará una
-- vez (queda en el historial) y la siguiente ejecución sale bien.

-- ─── 1. Renombrar tablas (idempotente) ──────────────────────────────────────────────
IF OBJECT_ID('vta.rvd_resumen_venta_diaria', 'U') IS NOT NULL
BEGIN
    EXEC sp_rename 'vta.rvd_resumen_venta_diaria', 'rvt_rvd_resumen_venta_diaria';
    EXEC sp_rename 'vta.PK_rvd_resumen_venta_diaria', 'PK_rvt_rvd_resumen_venta_diaria', 'OBJECT';
END;

IF OBJECT_ID('vta.cpr_control_proceso', 'U') IS NOT NULL
    EXEC sp_rename 'vta.cpr_control_proceso', 'rvt_cpr_control_proceso';
GO

-- ─── 2. Recalcular días ─────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE vta.rvd_RecalcularDias
    @dias vta.rvd_tienda_dia READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DELETE r
    FROM vta.rvt_rvd_resumen_venta_diaria r
    JOIN @dias d
        ON d.tienda = r.rvd_codigo_tie
       AND d.fecha  = r.rvd_fecha;

    INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
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

-- ─── 3. Incremental (una marca de agua por fuente) ──────────────────────────────────
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
        -- DATETIME: mismo tipo que FechaImportacion en ambas fuentes (ver 004).
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

-- ─── 4. Recalcular rango ────────────────────────────────────────────────────────────
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

-- ─── 5. Verificación ────────────────────────────────────────────────────────────────
-- Las tablas nuevas existen y las viejas ya no.
SELECT
    OBJECT_ID('vta.rvt_rvd_resumen_venta_diaria', 'U') AS resumen_nuevo,
    OBJECT_ID('vta.rvt_cpr_control_proceso', 'U')      AS control_nuevo,
    OBJECT_ID('vta.rvd_resumen_venta_diaria', 'U')     AS resumen_viejo_debe_ser_null,
    OBJECT_ID('vta.cpr_control_proceso', 'U')          AS control_viejo_debe_ser_null;

-- El incremental corre con los nombres nuevos y no deja error.
EXEC vta.rvd_ActualizarResumenIncremental;
SELECT cpr_proceso, cpr_ultima_fecha_importacion, cpr_ultima_ejecucion, cpr_dias_recalculados, cpr_ultimo_error
FROM vta.rvt_cpr_control_proceso;
GO
