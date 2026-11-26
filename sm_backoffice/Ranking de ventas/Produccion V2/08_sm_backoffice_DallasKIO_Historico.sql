-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ El script 10 reemplaza vta.rvd_ImportarVentaRanking (sección 2) y borra vta.rvd_FechaCorteKIO.
--   NO volver a correr este archivo después del 10: la importación fallaría al no encontrar la función.
-- ⚠ El script 11 borra vta.rvd_CargarHistoricoFecha (sección 3). Otro día pasado se carga desde Aloha on premise.
-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███   — NO en KIO
-- PRODUCCIÓN V2 · Dallas por KIO + carga del histórico de fechas especiales.
-- Requiere: 06 ejecutado (Azure) y 07 ejecutado (KIO). No crea tablas.
-- Idempotente. Reemplaza vta.rvd_ImportarVentaRanking del 06: NO volver a correr el 06 después.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- QUÉ CAMBIA
--   * Dallas se lee de la GNDSALE de cada tienda por KIO (SP_ObtenerVentaRankingUS), igual que GT/SV.
--     Mismas reglas: venta = TYPE 52 sin TYPEID 74, categoría por la caja (TYPEID2 del TYPE 44).
--     Hora del bloque = hora de cierre del check, convertida de hora de Dallas a hora de Guatemala.
--     Ya no se lee sm_pos.dbo.RankingGNDSALE en el día a día.
--   * Las reglas de cada fuente quedan en SPs internos (vta.rvd_DocumentosGT/SV/Gndsale) para usarlas
--     igual en el día a día y en la carga del histórico.
--   * vta.rvd_CargarHistoricoFecha: carga un día pasado en bloques de 15 min. Primero intenta las tiendas
--     por KIO; las que no tengan ese día los toma de FiscalInvoice (GT) o RankingGNDSALE (SV y Dallas).
--     Si tampoco hay datos, la tienda queda sin ese día (no operaba).

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificación previa ─────────────────────────────────────────────────────────
DECLARE @error NVARCHAR(400) =
    CASE
        WHEN OBJECT_ID('vta.rvd_GuardarDocumentos', 'P') IS NULL
            THEN N'No existe vta.rvd_GuardarDocumentos: correr antes Produccion V2/06.'
    END;

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Reglas por fuente ───────────────────────────────────────────────────────────
-- Cada SP lee una tabla temporal de staging del que lo llama y agrega los documentos a #documentos.

-- GT: facturas (1 suma, 10 resta). Lee #stg_gt (KIO o FiscalInvoice).
-- La propina viene por check: se reparte entre los documentos del mismo check y tipo según su TotalTxn.
-- En un reembolso (10) la propina viene negativa y sus montos en positivo: se usa su valor absoluto y el
-- signo lo aplica el reembolso, igual que Aloha. Factor = (TotalTxn - propina) / TotalTxn.
CREATE OR ALTER PROCEDURE vta.rvd_DocumentosGT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO #documentos
    SELECT c.categoria,
           CASE WHEN g.tipo = '10' THEN 1 ELSE 0 END,
           CASE WHEN g.tipo = '1'  THEN 1 ELSE 0 END,
           s.signo * g.TaxableAmount * f.factor,
           s.signo * g.TotalTax * f.factor,
           s.signo * (g.TotalTxn - g.propina),
           s.signo * g.propina,
           CASE WHEN g.tipo = '10' THEN g.TaxableAmount * f.factor ELSE 0 END,
           g.SysDate
    FROM (
        SELECT x.*,
               CASE WHEN x.PropinaCheck <> 0 THEN
                        CASE WHEN x.tipo = '10' THEN ABS(x.PropinaCheck) ELSE x.PropinaCheck END *
                        CASE WHEN SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo) = 0
                             THEN 1.0 / COUNT(*) OVER (PARTITION BY x.CheckNumber, x.tipo)
                             ELSE x.TotalTxn / SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo)
                        END
                    ELSE 0
               END AS propina
        FROM (
            SELECT st.TermId, st.CheckNumber, st.SysDate,
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
END;
GO

-- SV: 01 y 03 suman, 05 (anulación) ya viene negativo. VentaNeta = venta sin IVA y sin propina.
-- Lee #stg_sv (KIO).
CREATE OR ALTER PROCEDURE vta.rvd_DocumentosSV
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO #documentos
    SELECT c.categoria,
           CASE WHEN x.tipo = '05' THEN 1 ELSE 0 END,
           CASE WHEN x.tipo IN ('01', '03') THEN 1 ELSE 0 END,
           x.VentaNeta,
           x.VentaTotal - x.TenderTip - x.VentaNeta,
           x.VentaTotal - x.TenderTip,
           x.TenderTip,
           CASE WHEN x.tipo = '05' THEN -x.VentaNeta ELSE 0 END,
           x.SysDate
    FROM (
        SELECT st.TermId, st.SysDate,
               ISNULL(st.VentaNeta, 0)    AS VentaNeta,
               ISNULL(st.VentaTotal, 0)   AS VentaTotal,
               ISNULL(st.TenderTip, 0)    AS TenderTip,
               LTRIM(RTRIM(st.DocTypeId)) AS tipo
        FROM #stg_sv st
    ) x
    CROSS APPLY vta.rvd_CategoriaPorTerminal(x.TermId) c
    WHERE x.tipo IN ('01', '03', '05');
END;
GO

-- Formato Aloha (GNDSALE): un documento por check. Venta = TYPE 52 sin TYPEID 74 (propina);
-- categoría por la caja = TYPEID2 de su línea TYPE 44 (check sin TYPE 44 → 'otros').
-- Lee #stg_gnd (KIO de Dallas o RankingGNDSALE). Hora de cierre 0 = check sin cierre: va al bloque actual.
-- @hora_dallas = 1 convierte la hora de cierre de Dallas (Central, con horario de verano) a Guatemala.
CREATE OR ALTER PROCEDURE vta.rvd_DocumentosGndsale
    @fecha       DATE,
    @hora_dallas BIT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO #documentos
    SELECT c.categoria, 0, 1, k.venta, 0, k.venta, 0, 0, m.momento
    FROM (
        SELECT CheckNumber,
               SUM(CASE WHEN Tipo = 52 AND ISNULL(TypeId, 0) <> 74 THEN ISNULL(Amount, 0) ELSE 0 END) AS venta,
               MAX(CASE WHEN Tipo = 44 THEN TypeId2 END) AS caja,
               MAX(CloseHour) AS hora,
               MAX(CloseMin)  AS minuto
        FROM #stg_gnd
        GROUP BY CheckNumber
        HAVING SUM(CASE WHEN Tipo = 52 THEN 1 ELSE 0 END) > 0
    ) k
    CROSS APPLY vta.rvd_CategoriaPorTerminal(k.caja) c
    CROSS APPLY (
        SELECT CASE WHEN k.hora BETWEEN 1 AND 23 THEN
                        DATEADD(MINUTE, k.hora * 60 + ISNULL(k.minuto, 0), CAST(@fecha AS DATETIME2(0)))
               END AS local_tienda
    ) l
    CROSS APPLY (
        SELECT CAST(CASE WHEN @hora_dallas = 1
                         THEN CAST(l.local_tienda AT TIME ZONE 'Central Standard Time'
                                   AT TIME ZONE 'Central America Standard Time' AS DATETIME2(0))
                         ELSE l.local_tienda
                    END AS DATETIME) AS momento
    ) m;
END;
GO

-- ─── 2. Importación única ───────────────────────────────────────────────────────────
-- Reemplaza la del 06. GT, SV y Dallas por KIO, solo tiendas con tie_importar_venta = 1.
--   @historico = 1: permite GT/SV antes de la fecha de corte (solo lo usa vta.rvd_CargarHistoricoFecha).
CREATE OR ALTER PROCEDURE vta.rvd_ImportarVentaRanking
    @fecha           CHAR(8) = NULL,  -- YYYYMMDD; NULL = hoy
    @tienda_filtro   INT     = NULL,  -- código Aloha; NULL = todas
    @negocio_filtro  INT     = NULL,  -- 1 = GT, 2 = SV, 3 = USA; NULL = todos
    @reconstruir_dia BIT     = 0,     -- 1 = rehace todos los bloques del día
    @historico       BIT     = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();
    IF @fecha IS NULL
        SET @fecha = CONVERT(CHAR(8), GETDATE(), 112);
    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);

    -- Antes del corte, GT/SV de ese día salieron de FiscalInvoice: solo se tocan con @historico = 1.
    DECLARE @antes_del_corte BIT =
        CASE WHEN @historico = 0
              AND @fecha_dia < (SELECT fecha_corte FROM vta.rvd_FechaCorteKIO()) THEN 1 ELSE 0 END;

    IF @antes_del_corte = 1 AND @negocio_filtro IN (1, 2)
        THROW 50001, 'La fecha es anterior a la fecha de corte KIO: para cargarla usar vta.rvd_CargarHistoricoFecha.', 1;

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
      AND t.tie_codigo_neg IN (1, 2, 3)
      AND TRY_CONVERT(INT, t.tie_codigo_aloha) IS NOT NULL
      AND (@antes_del_corte = 0 OR t.tie_codigo_neg = 3)
      AND (@negocio_filtro IS NULL OR t.tie_codigo_neg = @negocio_filtro)
      AND (@tienda_filtro IS NULL OR TRY_CONVERT(INT, t.tie_codigo_aloha) = @tienda_filtro);

    -- Lo que devuelve cada SP de KIO (mismo orden y tipos que su WITH RESULT SETS).
    CREATE TABLE #stg_gt (
        DocTypeId NVARCHAR(5), TermId INT, DateOfBusiness DATETIME, CheckNumber INT,
        TaxableAmount DECIMAL(18, 4), TotalTax DECIMAL(18, 4), TotalTxn DECIMAL(18, 4),
        PropinaCheck DECIMAL(18, 4), SysDate DATETIME, GUID NVARCHAR(50)
    );
    CREATE TABLE #stg_sv (
        DocTypeId NVARCHAR(5), TermId INT, DateOfBusiness DATETIME, CheckNumber INT,
        VentaNeta DECIMAL(18, 4), VentaTotal DECIMAL(18, 4), TenderTip DECIMAL(18, 4),
        SysDate DATETIME, GUID NVARCHAR(50), OriginalInvoiceNo NVARCHAR(50)
    );
    CREATE TABLE #stg_gnd (
        CheckNumber INT, Tipo INT, TypeId INT, TypeId2 INT, Amount DECIMAL(18, 4), CloseHour INT, CloseMin INT
    );

    -- Documentos normalizados, con signo ya aplicado. Los lee vta.rvd_GuardarDocumentos.
    CREATE TABLE #documentos (
        categoria         VARCHAR(20)    NOT NULL,
        es_reembolso      INT            NOT NULL,
        cuenta_venta      INT            NOT NULL,
        venta_sin_iva     DECIMAL(18, 6) NOT NULL,
        iva               DECIMAL(18, 6) NOT NULL,
        venta_con_iva     DECIMAL(18, 6) NOT NULL,
        propina           DECIMAL(18, 6) NOT NULL,
        reembolso_sin_iva DECIMAL(18, 6) NOT NULL,  -- en positivo
        momento           DATETIME       NULL       -- a qué bloque pertenece si hay que reconstruirlo
    );

    DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM #tiendas);
    DECLARE @tienda INT, @ip NVARCHAR(128), @neg INT;
    DECLARE @sql NVARCHAR(MAX), @sqlKio NVARCHAR(MAX);
    DECLARE @t0 DATETIME2, @estado VARCHAR(20), @mensaje NVARCHAR(4000), @leidos INT;

    WHILE @i <= @max
    BEGIN
        SELECT @tienda = tienda, @ip = ip, @neg = codigo_neg FROM #tiendas WHERE id = @i;
        SELECT @t0 = SYSDATETIME(), @estado = NULL, @mensaje = NULL, @leidos = 0;

        BEGIN TRY
            TRUNCATE TABLE #stg_gt;
            TRUNCATE TABLE #stg_sv;
            TRUNCATE TABLE #stg_gnd;
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
                EXEC vta.rvd_DocumentosGT;
            END
            ELSE IF @neg = 2
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingSV] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [DocTypeId] nvarchar(5), [TermId] int, [DateOfBusiness] datetime, [CheckNumber] int,
                    [VentaNeta] decimal(18, 4), [VentaTotal] decimal(18, 4), [TenderTip] decimal(18, 4),
                    [SysDate] datetime, [GUID] nvarchar(50), [OriginalInvoiceNo] nvarchar(50)
                ))';
                SET @sql = N'INSERT INTO #stg_sv SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;
                EXEC vta.rvd_DocumentosSV;
            END
            ELSE
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingUS] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [CheckNumber] int, [Tipo] int, [TypeId] int, [TypeId2] int,
                    [Amount] decimal(18, 4), [CloseHour] int, [CloseMin] int
                ))';
                SET @sql = N'INSERT INTO #stg_gnd SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;
                EXEC vta.rvd_DocumentosGndsale @fecha = @fecha_dia, @hora_dallas = 1;
            END;

            SET @leidos = (SELECT COUNT(*) FROM #documentos);

            IF @leidos = 0
                SET @estado = 'SIN_DATOS';  -- no se graba ni se borra: queda la última foto buena
            ELSE
            BEGIN
                EXEC vta.rvd_GuardarDocumentos @fecha = @fecha_dia, @tienda = @tienda, @reconstruir = @reconstruir_dia;
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

-- ─── 3. Carga del histórico de un día ───────────────────────────────────────────────
-- Se corre a mano, una vez por fecha. Rehace los bloques de ese día:
--   1. Todas las tiendas por KIO (las tiendas conservan desde ~oct 2025 GT, ~abr 2026 SV, oct 2026 Dallas).
--   2. Las que quedaron sin datos: GT desde sm_pos.dbo.FiscalInvoice (hora = SysDate);
--      SV y Dallas desde sm_pos.dbo.RankingGNDSALE (hora de cierre del check).
--   3. Si tampoco hay datos, la tienda no operaba ese día: queda sin él (SIN_DATOS en la bitácora).
-- Al final devuelve, por tienda, de dónde salió el día.
CREATE OR ALTER PROCEDURE vta.rvd_CargarHistoricoFecha
    @fecha          CHAR(8),        -- YYYYMMDD
    @negocio_filtro INT = NULL      -- 1 = GT, 2 = SV, 3 = USA; NULL = todos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);
    DECLARE @inicio DATETIME2(0) = SYSDATETIME();

    IF @fecha_dia >= CAST(GETDATE() AS DATE)
        THROW 50003, 'La carga de histórico es solo para días pasados.', 1;

    -- 1. Tiendas por KIO.
    EXEC vta.rvd_ImportarVentaRanking
         @fecha = @fecha, @negocio_filtro = @negocio_filtro, @reconstruir_dia = 1, @historico = 1;

    -- 2. Tiendas que KIO no pudo cargar en esta corrida (SIN_DATOS o ERROR). Aunque ya tengan filas ese
    --    día (el total diario de antes de los bloques), se rehacen desde la otra fuente.
    DROP TABLE IF EXISTS #faltantes;
    CREATE TABLE #faltantes (id INT IDENTITY(1, 1) PRIMARY KEY, tienda INT NOT NULL, codigo_neg INT NOT NULL);

    INSERT INTO #faltantes (tienda, codigo_neg)
    SELECT TRY_CONVERT(INT, t.tie_codigo_aloha), t.tie_codigo_neg
    FROM [10.138.58.142].[sm_pos].[dbo].[aloha_tie_tienda] t WITH (NOLOCK)
    WHERE t.tie_estado = 1
      AND t.tie_importar_venta = 1
      AND t.tie_codigo_neg IN (1, 2, 3)
      AND TRY_CONVERT(INT, t.tie_codigo_aloha) IS NOT NULL
      AND (@negocio_filtro IS NULL OR t.tie_codigo_neg = @negocio_filtro)
      AND NOT EXISTS (SELECT 1 FROM vta.rvt_lik_log_importacion_kio l
                      WHERE l.lik_fecha_negocio = @fecha_dia
                        AND l.lik_codigo_tie = TRY_CONVERT(INT, t.tie_codigo_aloha)
                        AND l.lik_ejecucion >= @inicio
                        AND l.lik_estado = 'OK');

    CREATE TABLE #stg_gt (
        DocTypeId NVARCHAR(5), TermId INT, DateOfBusiness DATETIME, CheckNumber INT,
        TaxableAmount DECIMAL(18, 4), TotalTax DECIMAL(18, 4), TotalTxn DECIMAL(18, 4),
        PropinaCheck DECIMAL(18, 4), SysDate DATETIME, GUID NVARCHAR(50)
    );
    CREATE TABLE #stg_gnd (
        CheckNumber INT, Tipo INT, TypeId INT, TypeId2 INT, Amount DECIMAL(18, 4), CloseHour INT, CloseMin INT
    );
    CREATE TABLE #documentos (
        categoria VARCHAR(20) NOT NULL, es_reembolso INT NOT NULL, cuenta_venta INT NOT NULL,
        venta_sin_iva DECIMAL(18, 6) NOT NULL, iva DECIMAL(18, 6) NOT NULL, venta_con_iva DECIMAL(18, 6) NOT NULL,
        propina DECIMAL(18, 6) NOT NULL, reembolso_sin_iva DECIMAL(18, 6) NOT NULL, momento DATETIME NULL
    );

    DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM #faltantes);
    DECLARE @tienda INT, @neg INT, @fuente NVARCHAR(50), @estado VARCHAR(20), @mensaje NVARCHAR(4000),
            @leidos INT, @t0 DATETIME2, @hora_dallas BIT;

    WHILE @i <= @max
    BEGIN
        SELECT @tienda = tienda, @neg = codigo_neg FROM #faltantes WHERE id = @i;
        SELECT @t0 = SYSDATETIME(), @leidos = 0, @mensaje = NULL;

        BEGIN TRY
            TRUNCATE TABLE #stg_gt;
            TRUNCATE TABLE #stg_gnd;
            TRUNCATE TABLE #documentos;

            IF @neg = 1
            BEGIN
                SET @fuente = N'FiscalInvoice';
                INSERT INTO #stg_gt
                SELECT CAST(fi.DocTypeId AS NVARCHAR(5)), fi.TermId, fi.LC_DOB, fi.CheckNumber,
                       fi.TaxableAmount, fi.TotalTax, fi.TotalTxn, fi.Propina, fi.SysDate, fi.GUID
                FROM sm_pos.dbo.FiscalInvoice fi
                WHERE fi.LC_DOB = @fecha_dia
                  AND CONVERT(INT, fi.LC_UNIT) = @tienda
                  AND fi.DocTypeId IN (1, 10);
                EXEC vta.rvd_DocumentosGT;
            END
            ELSE
            BEGIN
                SET @fuente = N'RankingGNDSALE';
                INSERT INTO #stg_gnd
                SELECT g.[CHECK], g.TYPE, g.TYPEID, g.TYPEID2, g.AMOUNT, g.CLOSEHOUR, g.CLOSEMIN
                FROM sm_pos.dbo.RankingGNDSALE g
                WHERE g.LC_DOB = @fecha_dia
                  AND g.LC_UNIT = @tienda
                  AND g.TYPE IN (44, 52);
                SET @hora_dallas = CASE WHEN @neg = 3 THEN 1 ELSE 0 END;
                EXEC vta.rvd_DocumentosGndsale @fecha = @fecha_dia, @hora_dallas = @hora_dallas;
            END;

            SET @leidos = (SELECT COUNT(*) FROM #documentos);

            IF @leidos = 0
                SELECT @estado = 'SIN_DATOS', @mensaje = N'Histórico: sin datos en ' + @fuente + N' (la tienda no operaba o no hay registro)';
            ELSE
            BEGIN
                EXEC vta.rvd_GuardarDocumentos @fecha = @fecha_dia, @tienda = @tienda, @reconstruir = 1;
                SELECT @estado = 'OK', @mensaje = N'Histórico: ' + @fuente;
            END;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;
            SELECT @estado = 'ERROR', @mensaje = N'Histórico (' + @fuente + N'): ' + ERROR_MESSAGE();
        END CATCH;

        INSERT INTO vta.rvt_lik_log_importacion_kio (
            lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
            lik_documentos_leidos, lik_segundos, lik_mensaje)
        VALUES (
            @inicio, @fecha_dia, @tienda, @estado,
            @leidos, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, @mensaje);

        SET @i += 1;
    END;

    -- 3. Resumen: de dónde salió el día de cada tienda (la última lectura de esta carga).
    SELECT u.lik_codigo_tie AS tienda, u.lik_estado AS estado,
           ISNULL(u.lik_mensaje, N'KIO (tienda)') AS fuente, u.lik_documentos_leidos AS documentos
    FROM (
        SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.lik_codigo_tie ORDER BY l.lik_id DESC) AS orden
        FROM vta.rvt_lik_log_importacion_kio l
        WHERE l.lik_fecha_negocio = @fecha_dia AND l.lik_ejecucion >= @inicio
    ) u
    WHERE u.orden = 1
    ORDER BY u.lik_estado, u.lik_codigo_tie;
END;
GO

-- ─── 4. Permisos de la API ──────────────────────────────────────────────────────────
-- La API ahora lee también la bitácora (qué tiendas se importan) y el resumen completo (LY por hora).
-- Si los usuarios de la API leen por rol (db_datareader), no hace falta nada. Si no, reemplazar y correr:
-- GRANT SELECT ON vta.rvt_lik_log_importacion_kio  TO [<USUARIO_API_RANKING>];
-- GRANT SELECT ON vta.rvt_rvd_resumen_venta_diaria TO [<USUARIO_API_RANKING>];
GO

SET NOEXEC OFF;
GO

-- ════════════════════════════════════════════════════════════════════════════════════
-- 5. Pruebas y carga (AZURE, sm_backoffice) — correr a mano, en este orden
-- ════════════════════════════════════════════════════════════════════════════════════
/*
-- 5.1 Dallas por KIO, hoy: debe grabar las 3 tiendas con bloques desde la primera venta.
EXEC vta.rvd_ImportarVentaRanking @negocio_filtro = 3, @reconstruir_dia = 1;

SELECT rvd_codigo_tie, rvd_bloque, SUM(rvd_venta_sin_iva) AS acumulado, MAX(CAST(rvd_ultimo_bloque AS INT)) AS ultimo
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_fecha = CAST(GETDATE() AS DATE) AND rvd_codigo_tie IN (1001, 1002, 1003)
GROUP BY rvd_codigo_tie, rvd_bloque
ORDER BY rvd_codigo_tie, rvd_bloque;

-- 5.2 Un día de prueba del histórico (devuelve de dónde salió cada tienda).
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20251224';

-- 5.3 Si 5.2 se ve bien, las demás fechas especiales. El 15/09 solo Guatemala.
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20251231';
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20260106';
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20260214';
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20260510';
EXEC vta.rvd_CargarHistoricoFecha @fecha = '20260915', @negocio_filtro = 1;

-- 5.4 Bloques por fecha y país: tiendas con datos, bloques y total del día.
SELECT r.rvd_fecha, t.tie_codigo_neg AS negocio, COUNT(DISTINCT r.rvd_codigo_tie) AS tiendas,
       COUNT(DISTINCT r.rvd_bloque) AS bloques,
       SUM(CASE WHEN r.rvd_ultimo_bloque = 1 THEN r.rvd_venta_sin_iva ELSE 0 END) AS total_dia
FROM vta.rvt_rvd_resumen_venta_diaria r
LEFT JOIN vta.tie_tienda t ON t.tie_codigo = r.rvd_codigo_tie
WHERE r.rvd_fecha IN ('2025-12-24','2025-12-31','2026-01-06','2026-02-14','2026-05-10','2026-09-15')
GROUP BY r.rvd_fecha, t.tie_codigo_neg
ORDER BY r.rvd_fecha, negocio;
*/
