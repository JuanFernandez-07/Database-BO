-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ REEMPLAZADO POR "Produccion V2" (29/10/2026): vta.rvd_ImportarVentaRanking sustituye a
--   vta.rvd_ImportarVentaDesdeKIO. NO volver a ejecutar después de Produccion V2/02.
-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE (servidor de sm_backoffice / sm_pos / ALOHA) ███   — NO en KIO
-- PRODUCCIÓN · Ranking desde KIO · Paso 2 de 2 (requiere 06 ya ejecutado en KIO)
-- Sustituye a FiscalInvoice como fuente del ranking para GT y SV: trae la venta de cada tienda
-- por KIO, la suma y la escribe directo en vta.rvt_rvd_resumen_venta_diaria. USA no cambia.
-- Es idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- FECHA DE CORTE (sección 1): 2026-10-29 = desde ese día GT/SV salen de KIO.
-- Ejecutar SOLO cuando el 06 ya esté en KIO. Para revertir: dejar la función en '9999-12-31' y
-- recalcular desde el corte con vta.rvd_RecalcularResumenRango.
--   * Días anteriores al corte: siguen saliendo de FiscalInvoice (histórico intacto).
--   * Desde el corte: GT/SV solo los escribe vta.rvd_ImportarVentaDesdeKIO; el incremental y el
--     recálculo de FiscalInvoice los ignoran (vta.rvd_RecalcularDias, script 01).
--
-- Flujo (por tienda GT/SV activa con tie_importar_venta = 1):
--   1. Llama por OPENQUERY([10.138.58.142]) a SP_ObtenerVentaRankingGT/SV con la IP y la fecha.
--   2. Todo lo que devuelve es de la tienda consultada (mismo criterio que usp_ImportarInvoiceDesdeKIOGT).
--   3. Aplica las reglas del país, suma por categoría y reemplaza el día completo de esa tienda.
--      Cada corrida recalcula el día entero: lo que llegue tarde (propina en GNDITEM) se corrige solo.
--   4. Si KIO falla o devuelve 0 documentos, NO borra lo que ya había.
--
-- Reglas por país (validadas con datos, documentación 3.10):
--   GT: DocTypeId 1 suma, 10 resta. Propina = GNDITEM ITEM 999323 de la tienda; va DENTRO de
--       TaxableAmount/TotalTax/TotalTxn → se quita con factor (TotalTxn - Propina) / TotalTxn.
--   SV: 01 y 03 suman, 05 (anulación) se suma tal cual (ya es negativo). VentaNeta = venta sin IVA
--       (ya sin propina); propina = TenderTip; IVA = VentaTotal - TenderTip - VentaNeta.
--   Categoría por TermId (vta.rvd_CategoriaPorTerminal, igual que la vista de FiscalInvoice).
--   Fecha = día de negocio (DateOfBusiness).

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificación previa ─────────────────────────────────────────────────────────
DECLARE @error NVARCHAR(400) =
    CASE
        WHEN SCHEMA_ID('vta') IS NULL
            THEN N'No existe el esquema vta en sm_backoffice.'
        WHEN NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = N'10.138.58.142')
            THEN N'No existe el linked server [10.138.58.142] (KIO).'
        WHEN OBJECT_ID('vta.rvd_FechaCorteKIO', 'IF') IS NULL
            THEN N'Falta vta.rvd_FechaCorteKIO: ejecutar antes la versión actual de vta.rvd_RecalcularDias (script 01).'
    END;

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Fecha de corte ──────────────────────────────────────────────────────────────
CREATE OR ALTER FUNCTION vta.rvd_FechaCorteKIO ()
RETURNS TABLE
AS
RETURN
    SELECT CAST('2026-10-29' AS DATE) AS fecha_corte;
GO

-- ─── 2. Categoría por terminal ──────────────────────────────────────────────────────
-- Mismo mapeo que vta.vw_rvd_fiscal_invoice_neto (01). Si se cambia, cambiar ambos.
CREATE OR ALTER FUNCTION vta.rvd_CategoriaPorTerminal (@term_id INT)
RETURNS TABLE
AS
RETURN
    SELECT CASE
               WHEN @term_id BETWEEN 1 AND 5  THEN 'panaderia'
               WHEN @term_id BETWEEN 6 AND 15 THEN 'restaurante'
               ELSE 'otros'  -- Café (30-34), Delivery (35-36), Autoservicio (37-38) y cualquier otro
           END AS categoria;
GO

-- ─── 3. Bitácora ────────────────────────────────────────────────────────────────────
IF OBJECT_ID('vta.rvt_lik_log_importacion_kio', 'U') IS NULL
    CREATE TABLE vta.rvt_lik_log_importacion_kio (
        lik_id                BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_rvt_lik_log_importacion_kio PRIMARY KEY,
        lik_ejecucion         DATETIME2(0)   NOT NULL,  -- inicio de la corrida (igual para todas las tiendas)
        lik_fecha_negocio     DATE           NOT NULL,
        lik_codigo_tie        INT            NOT NULL,
        lik_estado            VARCHAR(20)    NOT NULL,  -- OK | SIN_DATOS | ERROR
        lik_documentos_leidos INT            NOT NULL,
        lik_segundos          DECIMAL(9, 2)  NOT NULL,
        lik_mensaje           NVARCHAR(4000) NULL
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rvt_lik_log_importacion_kio_fecha_tienda')
    CREATE INDEX IX_rvt_lik_log_importacion_kio_fecha_tienda
        ON vta.rvt_lik_log_importacion_kio (lik_fecha_negocio, lik_codigo_tie);
GO

-- ─── 4. SP de importación ───────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE vta.rvd_ImportarVentaDesdeKIO
    @fecha          CHAR(8) = NULL,  -- YYYYMMDD; NULL = hoy
    @tienda_filtro  INT     = NULL,  -- código Aloha; NULL = todas
    @negocio_filtro INT     = NULL   -- 1 = GT, 2 = SV; NULL = ambos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();
    IF @fecha IS NULL
        SET @fecha = CONVERT(CHAR(8), GETDATE(), 112);
    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);

    -- Antes del corte el día sale de FiscalInvoice: no se pisa el histórico.
    IF @fecha_dia < (SELECT fecha_corte FROM vta.rvd_FechaCorteKIO())
        THROW 50001, 'La fecha es anterior a la fecha de corte KIO: ese día sale de FiscalInvoice.', 1;

    DROP TABLE IF EXISTS #tiendas;
    CREATE TABLE #tiendas (
        id         INT IDENTITY(1, 1) PRIMARY KEY,
        tienda     INT           NOT NULL,
        ip         NVARCHAR(128) NOT NULL,
        codigo_neg INT           NOT NULL
    );

    INSERT INTO #tiendas (tienda, ip, codigo_neg)
    SELECT TRY_CONVERT(INT, t.tie_codigo_aloha), LTRIM(RTRIM(t.tie_ip)) + N'\SQLEXPRESS', t.tie_codigo_neg
    FROM [10.138.58.142].[sm_pos].[dbo].[aloha_tie_tienda] t WITH (NOLOCK)
    WHERE t.tie_ip IS NOT NULL AND LTRIM(RTRIM(t.tie_ip)) <> ''
      AND t.tie_estado = 1
      AND t.tie_importar_venta = 1
      AND t.tie_codigo_neg IN (1, 2)
      AND TRY_CONVERT(INT, t.tie_codigo_aloha) IS NOT NULL
      AND (@negocio_filtro IS NULL OR t.tie_codigo_neg = @negocio_filtro)
      AND (@tienda_filtro IS NULL OR TRY_CONVERT(INT, t.tie_codigo_aloha) = @tienda_filtro);

    -- Lo que devuelve cada SP de KIO (mismo orden y tipos que su WITH RESULT SETS).
    CREATE TABLE #stg_gt (
        DocTypeId      NVARCHAR(5),
        TermId         INT,
        DateOfBusiness DATETIME,
        CheckNumber    INT,
        TaxableAmount  DECIMAL(18, 4),
        TotalTax       DECIMAL(18, 4),
        TotalTxn       DECIMAL(18, 4),
        PropinaCheck   DECIMAL(18, 4),
        SysDate        DATETIME,
        GUID           NVARCHAR(50)
    );

    CREATE TABLE #stg_sv (
        DocTypeId         NVARCHAR(5),
        TermId            INT,
        DateOfBusiness    DATETIME,
        CheckNumber       INT,
        VentaNeta         DECIMAL(18, 4),
        VentaTotal        DECIMAL(18, 4),
        TenderTip         DECIMAL(18, 4),
        SysDate           DATETIME,
        GUID              NVARCHAR(50),
        OriginalInvoiceNo NVARCHAR(50)
    );

    -- Documentos normalizados (mismas columnas para ambos países), con signo ya aplicado.
    CREATE TABLE #documentos (
        categoria         VARCHAR(20)    NOT NULL,
        es_reembolso      INT            NOT NULL,
        cuenta_venta      INT            NOT NULL,
        venta_sin_iva     DECIMAL(18, 6) NOT NULL,
        iva               DECIMAL(18, 6) NOT NULL,
        venta_con_iva     DECIMAL(18, 6) NOT NULL,
        propina           DECIMAL(18, 6) NOT NULL,
        reembolso_sin_iva DECIMAL(18, 6) NOT NULL   -- en positivo
    );

    DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM #tiendas);
    DECLARE @tienda INT, @ip NVARCHAR(128), @neg INT;
    DECLARE @sql NVARCHAR(MAX), @sqlKio NVARCHAR(MAX);
    DECLARE @t0 DATETIME2, @estado VARCHAR(20), @mensaje NVARCHAR(4000), @leidos INT, @lock INT;

    WHILE @i <= @max
    BEGIN
        SELECT @tienda = tienda, @ip = ip, @neg = codigo_neg FROM #tiendas WHERE id = @i;
        SELECT @t0 = SYSDATETIME(), @estado = NULL, @mensaje = NULL, @leidos = 0;

        BEGIN TRY
            TRUNCATE TABLE #stg_gt;
            TRUNCATE TABLE #stg_sv;
            TRUNCATE TABLE #documentos;

            IF @neg = 1
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingGT] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [DocTypeId] nvarchar(5), [TermId] int, [DateOfBusiness] datetime, [CheckNumber] int,
                    [TaxableAmount] decimal(18, 4), [TotalTax] decimal(18, 4), [TotalTxn] decimal(18, 4),
                    [PropinaCheck] decimal(18, 4), [SysDate] datetime, [GUID] nvarchar(50)
                ))';
                SET @sql = N'INSERT INTO #stg_gt SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;

                -- La propina viene por check: se reparte entre las facturas (tipo 1) del mismo check
                -- según su TotalTxn. Los reembolsos (10) no llevan propina.
                INSERT INTO #documentos
                SELECT c.categoria,
                       CASE WHEN g.tipo = '10' THEN 1 ELSE 0 END,
                       CASE WHEN g.tipo = '1'  THEN 1 ELSE 0 END,
                       s.signo * g.TaxableAmount * f.factor,
                       s.signo * g.TotalTax * f.factor,
                       s.signo * (g.TotalTxn - g.propina),
                       s.signo * g.propina,
                       CASE WHEN g.tipo = '10' THEN g.TaxableAmount * f.factor ELSE 0 END
                FROM (
                    SELECT x.*,
                           CASE WHEN x.tipo = '1' AND x.PropinaCheck <> 0 THEN
                                    x.PropinaCheck *
                                    CASE WHEN SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo) = 0
                                         THEN 1.0 / COUNT(*) OVER (PARTITION BY x.CheckNumber, x.tipo)
                                         ELSE x.TotalTxn / SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo)
                                    END
                                ELSE 0
                           END AS propina
                    FROM (
                        SELECT st.TermId, st.CheckNumber,
                               ISNULL(st.TaxableAmount, 0) AS TaxableAmount,
                               ISNULL(st.TotalTax, 0)      AS TotalTax,
                               ISNULL(st.TotalTxn, 0)      AS TotalTxn,
                               ISNULL(st.PropinaCheck, 0)  AS PropinaCheck,
                               LTRIM(RTRIM(st.DocTypeId))  AS tipo
                        FROM #stg_gt st
                    ) x
                    WHERE x.tipo IN ('1', '10')
                ) g
                CROSS APPLY (SELECT CASE WHEN g.tipo = '10' THEN -1 ELSE 1 END AS signo) s
                CROSS APPLY (SELECT CASE WHEN g.TotalTxn = 0 THEN 1
                                         ELSE (g.TotalTxn - g.propina) / g.TotalTxn END AS factor) f
                CROSS APPLY vta.rvd_CategoriaPorTerminal(g.TermId) c;
            END
            ELSE
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingSV] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [DocTypeId] nvarchar(5), [TermId] int, [DateOfBusiness] datetime, [CheckNumber] int,
                    [VentaNeta] decimal(18, 4), [VentaTotal] decimal(18, 4), [TenderTip] decimal(18, 4),
                    [SysDate] datetime, [GUID] nvarchar(50), [OriginalInvoiceNo] nvarchar(50)
                ))';
                SET @sql = N'INSERT INTO #stg_sv SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;

                -- 05 (anulación) ya viene negativo: se suma tal cual y cuenta como reembolso.
                INSERT INTO #documentos
                SELECT c.categoria,
                       CASE WHEN x.tipo = '05' THEN 1 ELSE 0 END,
                       CASE WHEN x.tipo IN ('01', '03') THEN 1 ELSE 0 END,
                       x.VentaNeta,
                       x.VentaTotal - x.TenderTip - x.VentaNeta,
                       x.VentaTotal - x.TenderTip,
                       x.TenderTip,
                       CASE WHEN x.tipo = '05' THEN -x.VentaNeta ELSE 0 END
                FROM (
                    SELECT st.TermId,
                           ISNULL(st.VentaNeta, 0)    AS VentaNeta,
                           ISNULL(st.VentaTotal, 0)   AS VentaTotal,
                           ISNULL(st.TenderTip, 0)    AS TenderTip,
                           LTRIM(RTRIM(st.DocTypeId)) AS tipo
                    FROM #stg_sv st
                ) x
                CROSS APPLY vta.rvd_CategoriaPorTerminal(x.TermId) c
                WHERE x.tipo IN ('01', '03', '05');
            END;

            SET @leidos = (SELECT COUNT(*) FROM #documentos);

            IF @leidos = 0
                SET @estado = 'SIN_DATOS';  -- no se borra lo que ya había
            ELSE
            BEGIN
                BEGIN TRAN;
                    -- Mismo bloqueo que el incremental y el recálculo de FiscalInvoice.
                    EXEC @lock = sp_getapplock
                        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
                        @LockOwner = N'Transaction', @LockTimeout = 60000;
                    IF @lock < 0
                        THROW 50002, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

                    DELETE FROM vta.rvt_rvd_resumen_venta_diaria
                    WHERE rvd_fecha = @fecha_dia AND rvd_codigo_tie = @tienda;

                    INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
                        rvd_fecha, rvd_codigo_tie, rvd_categoria,
                        rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
                        rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en, rvd_propina)
                    SELECT @fecha_dia, @tienda, categoria,
                           SUM(venta_sin_iva), SUM(iva), SUM(venta_con_iva), SUM(reembolso_sin_iva),
                           SUM(cuenta_venta), SUM(es_reembolso), SYSDATETIME(), SUM(propina)
                    FROM #documentos
                    GROUP BY categoria;
                COMMIT;

                SET @estado = 'OK';
            END;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;
            SELECT @estado = 'ERROR', @mensaje = ERROR_MESSAGE();
        END CATCH;

        INSERT INTO vta.rvt_lik_log_importacion_kio (
            lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
            lik_documentos_leidos, lik_segundos, lik_mensaje)
        VALUES (
            @ejecucion, @fecha_dia, @tienda, @estado,
            @leidos, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, @mensaje);

        SET @i += 1;
    END;
END;
GO

SET NOEXEC OFF;
GO

-- 5. Job: está en 08_msdb_Job_ImportarVentaDesdeKIO.sql (msdb).

-- ════════════════════════════════════════════════════════════════════════════════════
-- 6. Consultas de revisión  (AZURE, sm_backoffice)
-- ════════════════════════════════════════════════════════════════════════════════════
/*
-- 6.1 Estado de la última corrida por tienda.
SELECT l.lik_codigo_tie, l.lik_estado, l.lik_documentos_leidos, l.lik_segundos, l.lik_mensaje
FROM vta.rvt_lik_log_importacion_kio l
WHERE l.lik_ejecucion = (SELECT MAX(lik_ejecucion) FROM vta.rvt_lik_log_importacion_kio)
ORDER BY l.lik_estado, l.lik_codigo_tie;

-- 6.2 Tiendas con documentos fuera de lo normal (linked server apuntando a otro servidor,
--     caso 212/213): una tienda normal lee cientos al día; miles = revisar.
SELECT l.lik_fecha_negocio, l.lik_codigo_tie, MAX(l.lik_documentos_leidos) AS documentos
FROM vta.rvt_lik_log_importacion_kio l
WHERE l.lik_fecha_negocio >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE)) AND l.lik_estado = 'OK'
GROUP BY l.lik_fecha_negocio, l.lik_codigo_tie
HAVING MAX(l.lik_documentos_leidos) > 3000
ORDER BY documentos DESC;

-- 6.3 SV contra Aloha (GNDSALE TYPE 52 = venta neta sin IVA). Deben coincidir.
DECLARE @dia_sv DATE = CAST(GETDATE() - 1 AS DATE);
SELECT g.LC_UNIT, g.aloha_52, r.venta_sin_iva, r.venta_sin_iva - g.aloha_52 AS diferencia
FROM (SELECT LC_UNIT, SUM(AMOUNT) AS aloha_52 FROM ALOHA.dbo.GNDSALE
      WHERE LC_DOB = @dia_sv AND TYPE = 52 GROUP BY LC_UNIT) g
JOIN (SELECT rvd_codigo_tie, SUM(rvd_venta_sin_iva) AS venta_sin_iva FROM vta.rvt_rvd_resumen_venta_diaria
      WHERE rvd_fecha = @dia_sv GROUP BY rvd_codigo_tie) r ON r.rvd_codigo_tie = g.LC_UNIT
WHERE g.LC_UNIT IN (SELECT tie_codigo FROM vta.tie_tienda WHERE tie_codigo_neg = 2)
ORDER BY g.LC_UNIT;
*/
