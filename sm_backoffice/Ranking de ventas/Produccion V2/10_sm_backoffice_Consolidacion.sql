-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███   — NO en KIO
-- PRODUCCIÓN V2 · Consolidación: menos objetos, misma lógica. Requiere 06, 08 y 09 ya ejecutados.
-- Correr COMPLETO y en una sola ejecución (la sección 4 compara contra la foto de la sección 0).
-- Idempotente. Después de este script NO volver a correr el 02, 06 ni el 08: recrearían los objetos
-- borrados aquí y vta.rvd_ImportarVentaRanking volvería a usar vta.rvd_FechaCorteKIO, que ya no existe.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- QUÉ CAMBIA
--   * vta.rvd_GuardarBloque se integra en vta.rvd_GuardarDocumentos (era su único usuario). Con eso
--     sobra el tipo tabla vta.rvd_resumen_bloque, que solo servía para pasarle las filas.
--   * vta.rvd_FechaCorteKIO() pasa a ser una variable dentro de vta.rvd_ImportarVentaRanking (único uso).
--   * Se borran: vta.rvd_GuardarBloque, el tipo vta.rvd_resumen_bloque y vta.rvd_FechaCorteKIO.
-- Las reglas, los bloques y lo que se graba no cambian. Los parámetros de los SP no cambian: el job,
-- vta.rvd_ReintentarDiasPendientes y vta.rvd_CargarHistoricoFecha siguen igual.

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificación previa y foto de control ───────────────────────────────────────
DECLARE @error NVARCHAR(4000) =
    CASE
        WHEN OBJECT_ID('vta.rvd_GuardarDocumentos', 'P') IS NULL
            THEN N'No existe vta.rvd_GuardarDocumentos: correr antes Produccion V2/06.'
        WHEN OBJECT_ID('vta.rvd_DocumentosGndsale', 'P') IS NULL
            THEN N'No existe vta.rvd_DocumentosGndsale: correr antes Produccion V2/08.'
    END;

-- Nadie más debe usar lo que se borra (fuera de los objetos que este script reemplaza o borra).
IF @error IS NULL
    SET @error = (
        SELECT N'Todavía lo usan: ' + STRING_AGG(OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id), ', ')
        FROM sys.sql_modules m
        WHERE (m.definition LIKE '%rvd[_]GuardarBloque%'
            OR m.definition LIKE '%rvd[_]resumen[_]bloque%'
            OR m.definition LIKE '%rvd[_]FechaCorteKIO%')
          AND OBJECT_NAME(m.object_id) NOT IN
              ('rvd_GuardarBloque', 'rvd_FechaCorteKIO', 'rvd_GuardarDocumentos', 'rvd_ImportarVentaRanking'));

IF @error IS NULL
    SET @error = (
        SELECT N'El job todavía lo usa: ' + STRING_AGG(j.name + N' / paso ' + CAST(s.step_id AS NVARCHAR(5)), ', ')
        FROM msdb.dbo.sysjobsteps s
        JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
        WHERE s.command LIKE '%rvd[_]GuardarBloque%'
           OR s.command LIKE '%rvd[_]resumen[_]bloque%'
           OR s.command LIKE '%rvd[_]FechaCorteKIO%');

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- Foto de dos días ya validados (Dallas 1001 08/11 y GT 134 29/10) para compararlos en la sección 4.
DROP TABLE IF EXISTS #antes;
SELECT rvd_fecha, rvd_codigo_tie, rvd_bloque, rvd_categoria, rvd_venta_sin_iva,
       rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_propina, rvd_ultimo_bloque
INTO #antes
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE (rvd_fecha = '2026-11-08' AND rvd_codigo_tie = 1001)
   OR (rvd_fecha = '2026-10-29' AND rvd_codigo_tie = 134);
GO

-- ─── 1. Grabar los documentos de una tienda (con la grabación del bloque integrada) ─
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

    DECLARE @minutos INT = (SELECT minutos FROM vta.rvd_IntervaloBloque());
    DECLARE @ahora DATETIME2(0) = SYSDATETIME();
    DECLARE @bloque_actual DATETIME2(0) = (SELECT bloque FROM vta.rvd_BloqueImportacion(@ahora));
    DECLARE @dia_anterior BIT = CASE WHEN @fecha < CAST(@ahora AS DATE) THEN 1 ELSE 0 END;
    DECLARE @lock INT, @primer_momento DATETIME2(0), @ultimo_momento DATETIME2(0);
    DECLARE @b DATETIME2(0), @fin DATETIME2(0), @es_ultimo BIT;

    -- Bloques a grabar, en orden. es_ultimo = 1: lleva todos los documentos y queda marcado como el
    -- último del día (el bloque actual, o el de la última venta al reconstruir un día anterior).
    DECLARE @bloques TABLE (bloque DATETIME2(0) PRIMARY KEY, es_ultimo BIT NOT NULL);

    -- Filas de un bloque (antes, el tipo vta.rvd_resumen_bloque). DECIMAL(18, 2) igual que el resumen.
    DECLARE @filas TABLE (
        categoria           VARCHAR(20)    NOT NULL PRIMARY KEY,
        venta_sin_iva       DECIMAL(18, 2) NOT NULL,
        iva                 DECIMAL(18, 2) NOT NULL,
        venta_con_iva       DECIMAL(18, 2) NOT NULL,
        reembolso_sin_iva   DECIMAL(18, 2) NOT NULL,
        cantidad_ventas     INT            NOT NULL,
        cantidad_reembolsos INT            NOT NULL,
        propina             DECIMAL(18, 2) NOT NULL
    );

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
            -- El bloque actual se agrega aparte, con todos los documentos.
            IF @fin >= @bloque_actual SET @fin = DATEADD(MINUTE, -@minutos, @bloque_actual);
        END;

        -- Bloques que faltan.
        WHILE @b <= @fin
        BEGIN
            INSERT INTO @bloques (bloque, es_ultimo)
            VALUES (@b, CASE WHEN @reconstruir = 1 AND @dia_anterior = 1 AND @b = @fin THEN 1 ELSE 0 END);
            SET @b = DATEADD(MINUTE, @minutos, @b);
        END;

        -- Bloque de la hora actual (no al reconstruir un día anterior que ya tiene su último bloque).
        IF NOT (@reconstruir = 1 AND @dia_anterior = 1 AND @fin IS NOT NULL)
            INSERT INTO @bloques (bloque, es_ultimo) VALUES (@bloque_actual, 1);

        -- Grabar cada bloque. Si ese (día, tienda) ya tiene el bloque, se reemplaza.
        SET @b = (SELECT MIN(bloque) FROM @bloques);
        WHILE @b IS NOT NULL
        BEGIN
            SET @es_ultimo = (SELECT es_ultimo FROM @bloques WHERE bloque = @b);

            DELETE FROM @filas;
            INSERT INTO @filas (
                categoria, venta_sin_iva, iva, venta_con_iva, reembolso_sin_iva,
                cantidad_ventas, cantidad_reembolsos, propina)
            SELECT categoria,
                   SUM(venta_sin_iva), SUM(iva), SUM(venta_con_iva), SUM(reembolso_sin_iva),
                   SUM(cuenta_venta), SUM(es_reembolso), SUM(propina)
            FROM #documentos
            WHERE momento <= @b OR @es_ultimo = 1
            GROUP BY categoria;

            IF EXISTS (SELECT 1 FROM @filas)
            BEGIN
                DELETE FROM vta.rvt_rvd_resumen_venta_diaria
                WHERE rvd_fecha = @fecha AND rvd_codigo_tie = @tienda AND rvd_bloque = @b;

                IF @es_ultimo = 1
                    UPDATE vta.rvt_rvd_resumen_venta_diaria
                    SET rvd_ultimo_bloque = 0
                    WHERE rvd_fecha = @fecha AND rvd_codigo_tie = @tienda AND rvd_ultimo_bloque = 1;

                INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
                    rvd_fecha, rvd_codigo_tie, rvd_categoria,
                    rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
                    rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en, rvd_propina,
                    rvd_bloque, rvd_ultimo_bloque)
                SELECT @fecha, @tienda, f.categoria,
                       f.venta_sin_iva, f.iva, f.venta_con_iva, f.reembolso_sin_iva,
                       f.cantidad_ventas, f.cantidad_reembolsos, @ahora, f.propina,
                       @b, @es_ultimo
                FROM @filas f;
            END;

            SET @b = (SELECT MIN(bloque) FROM @bloques WHERE bloque > @b);
        END;
    COMMIT;
END;
GO

-- ─── 2. Importación única (fecha de corte dentro del SP) ────────────────────────────
-- Igual que la del 08. GT, SV y Dallas por KIO, solo tiendas con tie_importar_venta = 1.
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

    -- Desde esta fecha GT y SV se leen por KIO. Antes salieron de FiscalInvoice (histórico cargado).
    DECLARE @fecha_corte_kio DATE = '2026-10-29';

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();
    IF @fecha IS NULL
        SET @fecha = CONVERT(CHAR(8), GETDATE(), 112);
    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);

    -- Antes del corte, GT/SV de ese día salieron de FiscalInvoice: solo se tocan con @historico = 1.
    DECLARE @antes_del_corte BIT =
        CASE WHEN @historico = 0 AND @fecha_dia < @fecha_corte_kio THEN 1 ELSE 0 END;

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

-- ─── 3. Borrar lo que quedó sin uso ─────────────────────────────────────────────────
-- Primero el SP (su parámetro usa el tipo), después el tipo.
DROP PROCEDURE IF EXISTS vta.rvd_GuardarBloque;
GO
IF TYPE_ID('vta.rvd_resumen_bloque') IS NOT NULL
    DROP TYPE vta.rvd_resumen_bloque;
GO
DROP FUNCTION IF EXISTS vta.rvd_FechaCorteKIO;
GO

-- ─── 4. Prueba: reconstruir los dos días de la foto y comparar ──────────────────────
-- Si KIO no responde, la tienda queda en ERROR en la bitácora y no se borra nada: repetir más tarde.
EXEC vta.rvd_ImportarVentaRanking @fecha = '20261108', @tienda_filtro = 1001, @negocio_filtro = 3, @reconstruir_dia = 1;
EXEC vta.rvd_ImportarVentaRanking @fecha = '20261029', @tienda_filtro = 134,  @negocio_filtro = 1, @reconstruir_dia = 1;
GO

-- Resultado de la lectura (las dos deben estar en OK).
SELECT TOP (2) lik_fecha_negocio, lik_codigo_tie, lik_estado, lik_documentos_leidos, lik_mensaje
FROM vta.rvt_lik_log_importacion_kio
WHERE lik_codigo_tie IN (1001, 134)
  AND lik_fecha_negocio IN ('2026-11-08', '2026-10-29')
ORDER BY lik_ejecucion DESC;

-- Diferencias contra la foto: debe devolver 0 filas.
WITH despues AS (
    SELECT rvd_fecha, rvd_codigo_tie, rvd_bloque, rvd_categoria, rvd_venta_sin_iva,
           rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_propina, rvd_ultimo_bloque
    FROM vta.rvt_rvd_resumen_venta_diaria
    WHERE (rvd_fecha = '2026-11-08' AND rvd_codigo_tie = 1001)
       OR (rvd_fecha = '2026-10-29' AND rvd_codigo_tie = 134)
)
SELECT 'solo antes' AS diferencia, * FROM (SELECT * FROM #antes EXCEPT SELECT * FROM despues) a
UNION ALL
SELECT 'solo después', * FROM (SELECT * FROM despues EXCEPT SELECT * FROM #antes) d
ORDER BY rvd_codigo_tie, rvd_bloque, rvd_categoria, diferencia;

-- Total del día: 1001 08/11 = 20,938.74 (validado contra KIO).
SELECT rvd_fecha, rvd_codigo_tie, SUM(rvd_venta_sin_iva) AS total_dia, COUNT(DISTINCT rvd_bloque) AS bloques
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE (rvd_fecha = '2026-11-08' AND rvd_codigo_tie = 1001 AND rvd_ultimo_bloque = 1)
   OR (rvd_fecha = '2026-10-29' AND rvd_codigo_tie = 134  AND rvd_ultimo_bloque = 1)
GROUP BY rvd_fecha, rvd_codigo_tie;

-- Un solo último bloque por día en todo el resumen: 0 filas.
SELECT rvd_fecha, rvd_codigo_tie
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_ultimo_bloque = 1
GROUP BY rvd_fecha, rvd_codigo_tie
HAVING COUNT(DISTINCT rvd_bloque) <> 1;
GO

SET NOEXEC OFF;
GO

-- ─── 5. Lo que queda del Ranking (referencia: 14 objetos y ningún tipo tabla) ───────
SELECT o.type_desc, o.name
FROM sys.objects o
WHERE SCHEMA_NAME(o.schema_id) = 'vta'
  AND (o.name LIKE 'rvd[_]%' OR o.name LIKE 'rvt[_]%' OR o.name LIKE 'vw[_]rvd[_]%')
ORDER BY o.type_desc, o.name;

SELECT name AS tipo_tabla FROM sys.types WHERE is_table_type = 1 AND SCHEMA_NAME(schema_id) = 'vta';
GO

-- Después de correrlo: revisar en la bitácora que la siguiente corrida del job quede en OK.
-- SELECT TOP (50) * FROM vta.rvt_lik_log_importacion_kio ORDER BY lik_ejecucion DESC;
