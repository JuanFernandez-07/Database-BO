-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN KIO (10.138.58.142), base sm_pos ███   — NO en Azure
-- PRODUCCIÓN · Ranking desde KIO · Paso 1 de 2 (el paso 2 es 07, en Azure)
-- SPs de solo lectura que consultan una tienda por su linked server (<IP>\SQLEXPRESS) y devuelven
-- sus facturas del día con lo que necesita el ranking. Los llama vta.rvd_ImportarVentaDesdeKIO
-- (Azure, 07_sm_backoffice_ImportarVentaDesdeKIO.sql). No modifican nada y no reemplazan a
-- SP_ObtenerFacturasPorTiendaGT/SV (siguen alimentando FiscalInvoice).
-- Es idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Las reglas de negocio (qué documentos suman/restan, factor de propina, categorías) NO van aquí:
-- se aplican en Azure. Estos SPs solo traen los datos crudos.

USE sm_pos;
GO

-- ─── GT ─────────────────────────────────────────────────────────────────────────────
-- Facturas de DBFISCAL_GT.dbo.Invoice (sin anuladas) + propina del check desde el GNDITEM de la
-- propia tienda (sm_pos.dbo.GNDITEM, ITEM 999323). La propina viene por CHECK: si un check tiene
-- varias facturas, Azure la reparte. Si la tienda aún no cargó la línea en GNDITEM, viene en 0 y la
-- siguiente corrida la toma (cada corrida recalcula el día completo).
CREATE OR ALTER PROCEDURE [dbo].[SP_ObtenerVentaRankingGT]
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
            i.[DocTypeId],
            i.[TermId],
            i.[DateOfBusiness],
            i.[CheckNumber],
            i.[TaxableAmount],
            i.[TotalTax],
            i.[TotalTxn],
            ISNULL(p.[Propina], 0) AS [PropinaCheck],
            i.[SysDate],
            i.[GUID]
        FROM [DBFISCAL_GT].[dbo].[Invoice] i WITH (NOLOCK)
        LEFT JOIN (
            -- En algunas tiendas (115, 130) GNDITEM tiene columnas nvarchar: se convierten.
            SELECT TRY_CAST([CHECK] AS int) AS [CHECK],
                   SUM(TRY_CAST([DISCPRIC] AS decimal(18, 4))) AS [Propina]
            FROM [sm_pos].[dbo].[GNDITEM] WITH (NOLOCK)
            WHERE [LC_DOB] = ''' + @fecha + N'''
              AND TRY_CAST([ITEM] AS int) = 999323
            GROUP BY TRY_CAST([CHECK] AS int)
        ) p ON p.[CHECK] = i.[CheckNumber]
        WHERE i.[DateOfBusiness] = ''' + @fecha + N'''
          AND (i.[IsVoid] = 0 OR i.[IsVoid] IS NULL)';

    SET @sql = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ip_tienda) + N', ''' + REPLACE(@sqlRemoto, '''', '''''') + N''');';

    EXEC sp_executesql @sql;
END;
GO

-- ─── SV ─────────────────────────────────────────────────────────────────────────────
-- Documentos de DBFISCAL_SALVADOR.dbo.Invoice del día: 01 Factura, 03 Comprobante de Crédito
-- Fiscal y 05 Anulación (montos ya negativos). Sin anulados por Status.
-- Diferencias con SP_ObtenerFacturasPorTiendaSV:
--   * Las 05 vienen aunque no tengan guid (no se certifican y el SP original las descarta). Sin
--     ellas la venta queda arriba de Aloha justo por lo anulado (validado 503151, 16–28/10/2026).
--   * La propina es TenderTip (VentaNeta ya viene sin propina ni IVA; Impuesto llega en 0).
CREATE OR ALTER PROCEDURE [dbo].[SP_ObtenerVentaRankingSV]
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
            CAST([Tipo] AS nvarchar(5))                             AS [DocTypeId],
            CAST([TermID] AS int)                                   AS [TermId],
            CAST([DOB] AS datetime)                                 AS [DateOfBusiness],
            CAST([CheckNumber] AS int)                              AS [CheckNumber],
            CAST(ISNULL([VentaNeta], 0) AS decimal(18, 4))          AS [VentaNeta],
            CAST(ISNULL([VentaTotal], 0) AS decimal(18, 4))         AS [VentaTotal],
            CAST(ISNULL([TenderTip], 0) AS decimal(18, 4))          AS [TenderTip],
            CAST([SysDate] AS datetime)                             AS [SysDate],
            CAST([guid] AS nvarchar(50))                            AS [GUID],
            CAST([OriginalInvoiceNo] AS nvarchar(50))               AS [OriginalInvoiceNo]
        FROM [DBFISCAL_SALVADOR].[dbo].[Invoice] WITH (NOLOCK)
        WHERE [DOB] = ''' + @fecha + N'''
          AND [Tipo] IN (''01'', ''03'', ''05'')
          AND UPPER(LTRIM(RTRIM(ISNULL([Status], '''')))) NOT IN (''ANULADA'', ''VOID'', ''ANULADO'')
          AND ([Tipo] = ''05'' OR LTRIM(RTRIM(ISNULL(CAST([guid] AS nvarchar(50)), ''''))) <> '''')';

    SET @sql = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@ip_tienda) + N', ''' + REPLACE(@sqlRemoto, '''', '''''') + N''');';

    EXEC sp_executesql @sql;
END;
GO

-- ─── Prueba (una tienda de cada país; cambiar IP y fecha) ───────────────────────────
-- EXEC [dbo].[SP_ObtenerVentaRankingGT] N'192.168.146.201\SQLEXPRESS', '20261028';  -- 134
-- EXEC [dbo].[SP_ObtenerVentaRankingSV] N'192.168.17.201\SQLEXPRESS', '20261028';   -- 503151
