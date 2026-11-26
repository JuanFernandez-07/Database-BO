-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ El script 08 reemplaza vta.rvd_ImportarVentaRanking (sección 4). NO volver a correr este archivo
--   después del 08: Dallas volvería a leerse de RankingGNDSALE.
-- ⚠ El script 10 integra vta.rvd_GuardarBloque en vta.rvd_GuardarDocumentos y borra el tipo
--   vta.rvd_resumen_bloque: este archivo ya no aplica.
-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███   — NO en KIO
-- PRODUCCIÓN V2 · Bloques que se corrigen solos. Requiere 02 ya ejecutado.
-- No crea tablas ni columnas. Idempotente: se puede volver a ejecutar.
-- Después de este script, correr de nuevo 03 (el job llama al reintento) y NO volver a correr 02.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- QUÉ AGREGA
--   * Relleno automático: si a una tienda le faltan bloques (sin conexión, turno saltado), la
--     siguiente corrida que la lea los crea con la hora de cada documento, antes de grabar el actual.
--       GT / SV: Invoice.SysDate (hora de la tienda; GT y SV son UTC-6, igual que el servidor).
--       USA: FechaImportacion, porque CLOSEHOUR está en hora de Dallas. Si RankingGNDSALE no se cargó
--            en esas horas, esos bloques repiten el acumulado anterior.
--     Solo llega hasta el bloque de la última venta: después de eso el acumulado ya no cambia.
--   * vta.rvd_ReintentarDiasPendientes: días anteriores (hasta 7) en los que la última lectura de una
--     tienda falló. Cubre a la tienda que vuelve después de las 03:59, cuando el job ya no lee ese día.
--   * @reconstruir_dia = 1: rehace todos los bloques de un día. Solo hace falta para días que ya
--     quedaron con huecos o con una regla vieja. Si la tienda no responde, no borra nada.
--
-- CÓMO DISTINGUIR UN BLOQUE RECONSTRUIDO: rvd_actualizado_en es muy posterior a rvd_bloque.
-- Un bloque reconstruido usa la hora de cada documento, no lo que se sabía a esa hora.

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificación previa ─────────────────────────────────────────────────────────
DECLARE @error NVARCHAR(400) =
    CASE
        WHEN COL_LENGTH('vta.rvt_rvd_resumen_venta_diaria', 'rvd_bloque') IS NULL
            THEN N'El resumen no tiene rvd_bloque: correr antes Produccion V2/02.'
        WHEN TYPE_ID('vta.rvd_resumen_bloque') IS NULL
            THEN N'No existe el tipo vta.rvd_resumen_bloque: correr antes Produccion V2/02.'
    END;

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Intervalo de los bloques ────────────────────────────────────────────────────
-- Si el job cambia de intervalo, cambiar el 15 aquí (y solo aquí).
CREATE OR ALTER FUNCTION vta.rvd_IntervaloBloque ()
RETURNS TABLE
AS
RETURN
    SELECT 15 AS minutos;
GO

CREATE OR ALTER FUNCTION vta.rvd_BloqueImportacion (@momento DATETIME2(0))
RETURNS TABLE
AS
RETURN
    SELECT CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, '20000101', @momento) / i.minutos * i.minutos,
                        CAST('20000101' AS DATETIME2(0))) AS DATETIME2(0)) AS bloque
    FROM vta.rvd_IntervaloBloque() i;
GO

-- ─── 2. Grabar un bloque ────────────────────────────────────────────────────────────
-- Interno. Quien lo llama abre la transacción y toma el bloqueo.
--   @bloque NULL = el de la hora actual. Otro valor = un bloque que faltaba.
--   @es_ultimo = 0: no toca la marca rvd_ultimo_bloque de los demás.
--   Si ese (día, tienda) ya tiene ese bloque, lo reemplaza.
CREATE OR ALTER PROCEDURE vta.rvd_GuardarBloque
    @filas     vta.rvd_resumen_bloque READONLY,
    @bloque    DATETIME2(0) = NULL,
    @es_ultimo BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ahora DATETIME2(0) = SYSDATETIME();
    IF @bloque IS NULL
        SET @bloque = (SELECT bloque FROM vta.rvd_BloqueImportacion(@ahora));

    DELETE r
    FROM vta.rvt_rvd_resumen_venta_diaria r
    WHERE r.rvd_bloque = @bloque
      AND EXISTS (SELECT 1 FROM @filas f WHERE f.fecha = r.rvd_fecha AND f.tienda = r.rvd_codigo_tie);

    IF @es_ultimo = 1
        UPDATE r
        SET r.rvd_ultimo_bloque = 0
        FROM vta.rvt_rvd_resumen_venta_diaria r
        WHERE r.rvd_ultimo_bloque = 1
          AND EXISTS (SELECT 1 FROM @filas f WHERE f.fecha = r.rvd_fecha AND f.tienda = r.rvd_codigo_tie);

    INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
        rvd_fecha, rvd_codigo_tie, rvd_categoria,
        rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
        rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en, rvd_propina,
        rvd_bloque, rvd_ultimo_bloque)
    SELECT f.fecha, f.tienda, f.categoria,
           f.venta_sin_iva, f.iva, f.venta_con_iva, f.reembolso_sin_iva,
           f.cantidad_ventas, f.cantidad_reembolsos, @ahora, f.propina,
           @bloque, @es_ultimo
    FROM @filas f;
END;
GO

-- ─── 3. Grabar los documentos de una tienda ─────────────────────────────────────────
-- Interno. Lee #documentos, que crea y llena vta.rvd_ImportarVentaRanking con todo el día de la tienda.
-- Graba los bloques que falten y después el de la hora actual. Si @reconstruir = 1, primero borra los
-- del día; en un día anterior no agrega un bloque con la hora actual: el de la última venta queda como último.
CREATE OR ALTER PROCEDURE vta.rvd_GuardarDocumentos
    @fecha       DATE,
    @tienda      INT,
    @reconstruir BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @filas vta.rvd_resumen_bloque;
    DECLARE @minutos INT = (SELECT minutos FROM vta.rvd_IntervaloBloque());
    DECLARE @ahora DATETIME2(0) = SYSDATETIME();
    DECLARE @bloque_actual DATETIME2(0) = (SELECT bloque FROM vta.rvd_BloqueImportacion(@ahora));
    DECLARE @dia_anterior BIT = CASE WHEN @fecha < CAST(@ahora AS DATE) THEN 1 ELSE 0 END;
    DECLARE @lock INT, @primer_momento DATETIME2(0), @ultimo_momento DATETIME2(0);
    DECLARE @b DATETIME2(0), @fin DATETIME2(0), @es_ultimo BIT;

    -- Hora fuera del día de negocio (00:00 a 06:00 del día siguiente): facturas en contingencia o
    -- certificadas días después. Quedan sin hora: cuentan en el total del día pero no generan bloques
    -- (una sola factura con fecha lejana armaría miles de bloques).
    UPDATE #documentos
    SET momento = NULL
    WHERE momento < CAST(@fecha AS DATETIME)
       OR momento >= DATEADD(HOUR, 30, CAST(@fecha AS DATETIME));

    SELECT @primer_momento = MIN(momento), @ultimo_momento = MAX(momento) FROM #documentos;

    BEGIN TRAN;
        EXEC @lock = sp_getapplock
            @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 60000;
        IF @lock < 0
            THROW 50002, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

        IF @reconstruir = 1
            DELETE FROM vta.rvt_rvd_resumen_venta_diaria
            WHERE rvd_fecha = @fecha AND rvd_codigo_tie = @tienda;

        SET @b = (SELECT MAX(rvd_bloque) FROM vta.rvt_rvd_resumen_venta_diaria
                  WHERE rvd_fecha = @fecha AND rvd_codigo_tie = @tienda);

        IF @b IS NOT NULL
            SET @b = DATEADD(MINUTE, @minutos, @b);
        ELSE IF @primer_momento IS NOT NULL
        BEGIN
            -- Sin bloques: el primero es el que ya incluye la primera venta.
            SET @b = (SELECT bloque FROM vta.rvd_BloqueImportacion(@primer_momento));
            IF @b < @primer_momento SET @b = DATEADD(MINUTE, @minutos, @b);
        END;

        IF @ultimo_momento IS NOT NULL
        BEGIN
            -- Bloque que ya incluye la última venta.
            SET @fin = (SELECT bloque FROM vta.rvd_BloqueImportacion(@ultimo_momento));
            IF @fin < @ultimo_momento SET @fin = DATEADD(MINUTE, @minutos, @fin);
            -- El bloque actual se graba abajo con todos los documentos.
            IF @fin >= @bloque_actual SET @fin = DATEADD(MINUTE, -@minutos, @bloque_actual);
        END;

        WHILE @b <= @fin
        BEGIN
            SET @es_ultimo = CASE WHEN @reconstruir = 1 AND @dia_anterior = 1 AND @b = @fin THEN 1 ELSE 0 END;

            DELETE FROM @filas;
            INSERT INTO @filas (
                fecha, tienda, categoria, venta_sin_iva, iva, venta_con_iva, reembolso_sin_iva,
                cantidad_ventas, cantidad_reembolsos, propina)
            SELECT @fecha, @tienda, categoria,
                   SUM(venta_sin_iva), SUM(iva), SUM(venta_con_iva), SUM(reembolso_sin_iva),
                   SUM(cuenta_venta), SUM(es_reembolso), SUM(propina)
            FROM #documentos
            WHERE momento <= @b OR @es_ultimo = 1
            GROUP BY categoria;

            IF EXISTS (SELECT 1 FROM @filas)
                EXEC vta.rvd_GuardarBloque @filas = @filas, @bloque = @b, @es_ultimo = @es_ultimo;

            SET @b = DATEADD(MINUTE, @minutos, @b);
        END;

        IF NOT (@reconstruir = 1 AND @dia_anterior = 1 AND @fin IS NOT NULL)
        BEGIN
            DELETE FROM @filas;
            INSERT INTO @filas (
                fecha, tienda, categoria, venta_sin_iva, iva, venta_con_iva, reembolso_sin_iva,
                cantidad_ventas, cantidad_reembolsos, propina)
            SELECT @fecha, @tienda, categoria,
                   SUM(venta_sin_iva), SUM(iva), SUM(venta_con_iva), SUM(reembolso_sin_iva),
                   SUM(cuenta_venta), SUM(es_reembolso), SUM(propina)
            FROM #documentos
            GROUP BY categoria;

            EXEC vta.rvd_GuardarBloque @filas = @filas;
        END;
    COMMIT;
END;
GO

-- ─── 4. Importación única ───────────────────────────────────────────────────────────
-- Reemplaza la de Produccion V2/02. Reglas por país: documentación 3.10 y 3.11.
CREATE OR ALTER PROCEDURE vta.rvd_ImportarVentaRanking
    @fecha           CHAR(8) = NULL,  -- YYYYMMDD; NULL = hoy
    @tienda_filtro   INT     = NULL,  -- código Aloha; NULL = todas
    @negocio_filtro  INT     = NULL,  -- 1 = GT, 2 = SV, 3 = USA; NULL = todos
    @reconstruir_dia BIT     = 0      -- 1 = rehace todos los bloques del día
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();
    IF @fecha IS NULL
        SET @fecha = CONVERT(CHAR(8), GETDATE(), 112);
    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);

    DECLARE @antes_del_corte BIT =
        CASE WHEN @fecha_dia < (SELECT fecha_corte FROM vta.rvd_FechaCorteKIO()) THEN 1 ELSE 0 END;

    IF @antes_del_corte = 1 AND @negocio_filtro IN (1, 2)
        THROW 50001, 'La fecha es anterior a la fecha de corte KIO: la venta de GT/SV de ese día salió de FiscalInvoice.', 1;

    -- ═══ 4.1 GT / SV por KIO ═══
    DROP TABLE IF EXISTS #tiendas;
    CREATE TABLE #tiendas (
        id         INT IDENTITY(1, 1) PRIMARY KEY,
        tienda     INT           NOT NULL,
        ip         NVARCHAR(128) NOT NULL,
        codigo_neg INT           NOT NULL
    );

    IF @antes_del_corte = 0 AND (@negocio_filtro IS NULL OR @negocio_filtro IN (1, 2))
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

                -- La propina viene por check: se reparte entre los documentos del mismo check y tipo
                -- según su TotalTxn. En un reembolso (10) GNDITEM la trae negativa y sus montos vienen
                -- en positivo: se usa su valor absoluto y el signo lo aplica el reembolso, igual que Aloha.
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

    -- ═══ 4.2 USA desde RankingGNDSALE ═══
    -- Una tienda a la vez, con el mismo guardado que GT/SV. Documentos leídos = checks.
    IF @negocio_filtro IS NULL OR @negocio_filtro = 3
    BEGIN
        DROP TABLE IF EXISTS #tiendas_usa;
        CREATE TABLE #tiendas_usa (id INT IDENTITY(1, 1) PRIMARY KEY, tienda INT NOT NULL);
        SET @t0 = SYSDATETIME();

        BEGIN TRY
            INSERT INTO #tiendas_usa (tienda)
            SELECT DISTINCT v.tienda
            FROM vta.vw_rvd_gndsale_neto v
            WHERE v.fecha = @fecha_dia
              AND (@tienda_filtro IS NULL OR v.tienda = @tienda_filtro);
        END TRY
        BEGIN CATCH
            -- Tienda 0 = toda la parte de USA: no se pudo leer qué tiendas hay.
            INSERT INTO vta.rvt_lik_log_importacion_kio (
                lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
                lik_documentos_leidos, lik_segundos, lik_mensaje)
            VALUES (
                @ejecucion, @fecha_dia, 0, 'ERROR',
                0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, N'USA: ' + ERROR_MESSAGE());
        END CATCH;

        SELECT @i = 1, @max = (SELECT MAX(id) FROM #tiendas_usa);

        WHILE @i <= @max
        BEGIN
            SELECT @tienda = tienda FROM #tiendas_usa WHERE id = @i;
            SELECT @t0 = SYSDATETIME(), @estado = NULL, @mensaje = N'USA (RankingGNDSALE)', @leidos = 0;

            BEGIN TRY
                TRUNCATE TABLE #documentos;

                INSERT INTO #documentos
                SELECT v.categoria, 0, 1,
                       SUM(v.venta_sin_iva), SUM(v.iva), SUM(v.venta_con_iva), SUM(v.propina), 0,
                       MAX(v.FechaImportacion)
                FROM vta.vw_rvd_gndsale_neto v
                WHERE v.fecha = @fecha_dia AND v.tienda = @tienda
                GROUP BY v.numero_check, v.categoria;

                SET @leidos = (SELECT COUNT(*) FROM #documentos);

                EXEC vta.rvd_GuardarDocumentos @fecha = @fecha_dia, @tienda = @tienda, @reconstruir = @reconstruir_dia;
                SET @estado = 'OK';
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK;
                SELECT @estado = 'ERROR', @mensaje = N'USA: ' + ERROR_MESSAGE();
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
END;
GO

-- ─── 5. Reintento de días anteriores ────────────────────────────────────────────────
-- Lo llama el job en cada corrida. Vuelve a leer los (día, tienda) de los últimos 7 días cuya última
-- lectura falló. Si la tienda sigue sin responder, solo agrega otro ERROR y se reintenta en el siguiente turno.
CREATE OR ALTER PROCEDURE vta.rvd_ReintentarDiasPendientes
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
    DECLARE @dia DATE, @dia_txt CHAR(8), @tienda INT;

    DECLARE pendientes CURSOR LOCAL FAST_FORWARD FOR
        SELECT u.lik_fecha_negocio, u.lik_codigo_tie
        FROM (
            SELECT l.lik_fecha_negocio, l.lik_codigo_tie, l.lik_estado,
                   ROW_NUMBER() OVER (PARTITION BY l.lik_fecha_negocio, l.lik_codigo_tie
                                      ORDER BY l.lik_ejecucion DESC, l.lik_id DESC) AS orden
            FROM vta.rvt_lik_log_importacion_kio l
            WHERE l.lik_fecha_negocio >= DATEADD(DAY, -7, @hoy)
              AND l.lik_fecha_negocio < @hoy
        ) u
        WHERE u.orden = 1 AND u.lik_estado = 'ERROR'
        ORDER BY u.lik_fecha_negocio, u.lik_codigo_tie;

    OPEN pendientes;
    FETCH NEXT FROM pendientes INTO @dia, @tienda;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @dia_txt = CONVERT(CHAR(8), @dia, 112);

        IF @tienda = 0
            EXEC vta.rvd_ImportarVentaRanking @fecha = @dia_txt, @negocio_filtro = 3;
        ELSE
            EXEC vta.rvd_ImportarVentaRanking @fecha = @dia_txt, @tienda_filtro = @tienda;

        FETCH NEXT FROM pendientes INTO @dia, @tienda;
    END;
    CLOSE pendientes;
    DEALLOCATE pendientes;
END;
GO

SET NOEXEC OFF;
GO

-- ════════════════════════════════════════════════════════════════════════════════════
-- 6. Pruebas (AZURE, sm_backoffice) — correr a mano, después de 06 y 03
-- ════════════════════════════════════════════════════════════════════════════════════
/*
-- 6.1 Reconstruir el 29/10 de una tienda y ver sus bloques.
EXEC vta.rvd_ImportarVentaRanking @fecha = '20261029', @tienda_filtro = 134, @negocio_filtro = 1, @reconstruir_dia = 1;

SELECT rvd_bloque, SUM(rvd_venta_sin_iva) AS acumulado, SUM(rvd_propina) AS propina,
       MAX(rvd_actualizado_en) AS grabado_en, MAX(CAST(rvd_ultimo_bloque AS INT)) AS ultimo
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_fecha = '2026-10-29' AND rvd_codigo_tie = 134
GROUP BY rvd_bloque
ORDER BY rvd_bloque;

-- 6.2 Integridad: un solo bloque marcado como último por (día, tienda). 0 filas.
SELECT rvd_fecha, rvd_codigo_tie
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_ultimo_bloque = 1
GROUP BY rvd_fecha, rvd_codigo_tie
HAVING COUNT(DISTINCT rvd_bloque) <> 1;

-- 6.3 Si la prueba cuadra: el 29/10 de todas las tiendas (una sola vez).
EXEC vta.rvd_ImportarVentaRanking @fecha = '20261029', @reconstruir_dia = 1;
*/
