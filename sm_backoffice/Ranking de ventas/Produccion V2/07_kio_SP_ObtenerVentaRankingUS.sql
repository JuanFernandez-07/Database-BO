-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN KIO (10.138.58.142), base sm_pos ███   — NO en Azure
-- PRODUCCIÓN V2 · Dallas desde las tiendas. Lo llama vta.rvd_ImportarVentaRanking (script 08, Azure).
-- Solo lectura. Idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Devuelve las líneas TYPE 44 (caja del check en TYPEID2) y TYPE 52 (venta por TYPEID) del día, de
-- sm_pos.dbo.GNDSALE de la tienda. En las tiendas de Dallas todas las columnas son nvarchar: se
-- convierten aquí. Las reglas (sin TYPEID 74, categoría por caja, hora de Dallas) se aplican en Azure.

USE sm_pos;
GO

CREATE OR ALTER PROCEDURE [dbo].[SP_ObtenerVentaRankingUS]
    @ip_tienda NVARCHAR(128),
    @fecha     CHAR(8)          -- YYYYMMDD
AS
BEGIN
    SET NOCOUNT ON;

    IF @fecha NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
        THROW 50001, 'Fecha inválida: formato YYYYMMDD.', 1;

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @sqlRemoto NVARCHAR(MAX);

    SET @sqlRemoto = N'
        SELECT
            TRY_CAST([CHECK] AS int)              AS [CheckNumber],
            TRY_CAST([TYPE] AS int)               AS [Tipo],
            TRY_CAST([TYPEID] AS int)             AS [TypeId],
            TRY_CAST([TYPEID2] AS int)            AS [TypeId2],
            TRY_CAST([AMOUNT] AS decimal(18, 4))  AS [Amount],
            TRY_CAST([CLOSEHOUR] AS int)          AS [CloseHour],
            TRY_CAST([CLOSEMIN] AS int)           AS [CloseMin]
        FROM [sm_pos].[dbo].[GNDSALE] WITH (NOLOCK)
        WHERE [LC_DOB] = ''' + @fecha + N'''
          AND TRY_CAST([TYPE] AS int) IN (44, 52)';

    SET @sql = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ip_tienda) + N', ''' + REPLACE(@sqlRemoto, '''', '''''') + N''');';

    EXEC sp_executesql @sql;
END;
GO

-- ─── Prueba (tienda 1001) ───────────────────────────────────────────────────────────
-- EXEC [dbo].[SP_ObtenerVentaRankingUS] N'172.20.8.101\SQLEXPRESS', '20261108';
