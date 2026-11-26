-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_pos ███   — NO en KIO
-- Conexión de tiendas · Paso 1 de 2: tabla de log y procedimiento de validación.
-- Idempotente: se puede volver a ejecutar (la tabla no se borra si ya existe).
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Para dar soporte a la lectura de cajas desde Azure: cada corrida prueba la conexión con todas las
-- tiendas activas que importan venta (aloha_tie_tienda en KIO: tie_estado = 1 y tie_importar_venta = 1)
-- y registra por tienda OK o ERROR con el motivo.
-- La prueba hace el mismo camino que la importación del Ranking: Azure → KIO [10.138.58.142] →
-- tienda (IP\SQLEXPRESS), con un SELECT 1 en la tienda. No lee ventas.
-- Independiente del Ranking: no toca vta.rvt_lik_log_importacion_kio ni ningún objeto de sm_backoffice.

USE sm_pos;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificación previa ─────────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = N'10.138.58.142')
BEGIN
    RAISERROR(N'No existe el servidor vinculado [10.138.58.142] (KIO). No se ejecutó nada.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Tabla de log ────────────────────────────────────────────────────────────────
-- Una fila por tienda y corrida. Tienda 0 = la corrida no pudo leer la lista de tiendas en KIO.
IF OBJECT_ID('dbo.TLS_LogConexionTienda', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TLS_LogConexionTienda (
        tls_id          BIGINT IDENTITY(1, 1) NOT NULL,
        tls_ejecucion   DATETIME2(0)   NOT NULL,  -- inicio de la corrida (igual para todas sus tiendas)
        tls_codigo_tie  INT            NOT NULL,  -- tie_codigo_aloha
        tls_codigo_neg  INT            NULL,      -- 1 GT, 2 SV, 3 USA
        tls_ip          NVARCHAR(128)  NULL,      -- servidor probado (IP\SQLEXPRESS)
        tls_estado      VARCHAR(10)    NOT NULL,  -- OK / ERROR
        tls_segundos    DECIMAL(9, 2)  NULL,      -- lo que tardó la prueba
        tls_mensaje     NVARCHAR(4000) NULL,      -- motivo del error
        CONSTRAINT PK_TLS_LogConexionTienda PRIMARY KEY CLUSTERED (tls_id),
        CONSTRAINT CK_TLS_LogConexionTienda_estado CHECK (tls_estado IN ('OK', 'ERROR'))
    );

    CREATE INDEX IX_TLS_LogConexionTienda_tienda
        ON dbo.TLS_LogConexionTienda (tls_codigo_tie, tls_ejecucion)
        INCLUDE (tls_estado);

    CREATE INDEX IX_TLS_LogConexionTienda_ejecucion
        ON dbo.TLS_LogConexionTienda (tls_ejecucion)
        INCLUDE (tls_codigo_tie, tls_estado);
END;
GO

-- ─── 2. Procedimiento de validación ─────────────────────────────────────────────────
-- Prueba todas las tiendas, una por una. Una tienda que falla no detiene a las demás.
-- Una tienda sin respuesta tarda ~20 s en dar error (tiempo de espera de la conexión).
CREATE OR ALTER PROCEDURE dbo.usp_TLS_ValidarConexionTiendas
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();

    DROP TABLE IF EXISTS #tiendas;
    CREATE TABLE #tiendas (
        id         INT IDENTITY(1, 1) PRIMARY KEY,
        tienda     INT           NOT NULL,
        ip         NVARCHAR(128) NOT NULL,
        codigo_neg INT           NULL
    );

    BEGIN TRY
        INSERT INTO #tiendas (tienda, ip, codigo_neg)
        SELECT TRY_CONVERT(INT, t.tie_codigo_aloha), LTRIM(RTRIM(t.tie_ip)) + N'\SQLEXPRESS', t.tie_codigo_neg
        FROM [10.138.58.142].[sm_pos].[dbo].[aloha_tie_tienda] t WITH (NOLOCK)
        WHERE t.tie_estado = 1
          AND t.tie_importar_venta = 1
          AND t.tie_ip IS NOT NULL AND LTRIM(RTRIM(t.tie_ip)) <> ''
          AND TRY_CONVERT(INT, t.tie_codigo_aloha) IS NOT NULL;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        -- Sin lista de tiendas no hay nada que probar: KIO no respondió.
        INSERT INTO dbo.TLS_LogConexionTienda (tls_ejecucion, tls_codigo_tie, tls_estado, tls_mensaje)
        VALUES (@ejecucion, 0, 'ERROR', N'No se pudo leer la lista de tiendas en KIO: ' + ERROR_MESSAGE());
        RETURN;
    END CATCH;

    DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM #tiendas);
    DECLARE @tienda INT, @ip NVARCHAR(128), @neg INT;
    DECLARE @sql NVARCHAR(MAX), @sqlKio NVARCHAR(MAX), @ok INT;
    DECLARE @t0 DATETIME2, @estado VARCHAR(10), @mensaje NVARCHAR(4000);

    WHILE @i <= @max
    BEGIN
        SELECT @tienda = tienda, @ip = ip, @neg = codigo_neg FROM #tiendas WHERE id = @i;
        SELECT @t0 = SYSDATETIME(), @estado = NULL, @mensaje = NULL, @ok = NULL;

        BEGIN TRY
            -- Se ejecuta en KIO: un SELECT 1 en la tienda.
            SET @sqlKio = N'SELECT ok FROM OPENQUERY(' + QUOTENAME(@ip) + N', ''SELECT 1 AS ok'')';
            SET @sql = N'SELECT @ok = ok FROM OPENQUERY([10.138.58.142], '''
                     + REPLACE(@sqlKio, '''', '''''') + N''');';
            EXEC sp_executesql @sql, N'@ok INT OUTPUT', @ok = @ok OUTPUT;

            IF @ok = 1
                SET @estado = 'OK';
            ELSE
                SELECT @estado = 'ERROR', @mensaje = N'La tienda respondió sin resultado.';
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK;
            SELECT @estado = 'ERROR', @mensaje = ERROR_MESSAGE();
        END CATCH;

        INSERT INTO dbo.TLS_LogConexionTienda (
            tls_ejecucion, tls_codigo_tie, tls_codigo_neg, tls_ip, tls_estado, tls_segundos, tls_mensaje)
        VALUES (
            @ejecucion, @tienda, @neg, @ip, @estado,
            DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, @mensaje);

        SET @i += 1;
    END;

    -- Resumen de la corrida.
    SELECT tls_estado, COUNT(*) AS tiendas
    FROM dbo.TLS_LogConexionTienda
    WHERE tls_ejecucion = @ejecucion
    GROUP BY tls_estado;
END;
GO

SET NOEXEC OFF;
GO

-- ─── 3. Prueba (correr a mano una vez) ──────────────────────────────────────────────
-- Tarda ~1-2 min (más ~20 s por cada tienda sin conexión).
-- EXEC dbo.usp_TLS_ValidarConexionTiendas;

-- ─── 4. Consultas de soporte ────────────────────────────────────────────────────────
-- Tiendas con error en la última corrida.
-- SELECT l.tls_codigo_tie, l.tls_codigo_neg, l.tls_ip, l.tls_segundos, l.tls_mensaje
-- FROM dbo.TLS_LogConexionTienda l
-- WHERE l.tls_ejecucion = (SELECT MAX(tls_ejecucion) FROM dbo.TLS_LogConexionTienda)
--   AND l.tls_estado = 'ERROR'
-- ORDER BY l.tls_codigo_tie;

-- Historial de una tienda.
-- SELECT tls_ejecucion, tls_estado, tls_segundos, tls_mensaje
-- FROM dbo.TLS_LogConexionTienda
-- WHERE tls_codigo_tie = <tienda>
-- ORDER BY tls_ejecucion DESC;

-- Tiendas con más errores en los últimos 7 días.
-- SELECT tls_codigo_tie, COUNT(*) AS pruebas,
--        SUM(CASE WHEN tls_estado = 'ERROR' THEN 1 ELSE 0 END) AS errores,
--        MAX(CASE WHEN tls_estado = 'ERROR' THEN tls_ejecucion END) AS ultimo_error
-- FROM dbo.TLS_LogConexionTienda
-- WHERE tls_ejecucion >= DATEADD(DAY, -7, SYSDATETIME())
-- GROUP BY tls_codigo_tie
-- HAVING SUM(CASE WHEN tls_estado = 'ERROR' THEN 1 ELSE 0 END) > 0
-- ORDER BY errores DESC;
