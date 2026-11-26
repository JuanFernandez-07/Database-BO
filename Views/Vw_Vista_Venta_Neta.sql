-- =============================================
-- Vista: plh.Vw_Vista_Venta_Neta
-- Desc:  Expone las ventas monetarias desde [ALOHA].[dbo].[GNDSALE].
--        Se usa como denominador en fn_plh_FactoresSKU para calcular
--        la venta neta mensual de la tienda:
--            Factor_SKU = Consumo_SKU / (SUM(AMOUNT) / 1000)
-- Columnas expuestas:
--   LC_DOB   → fecha de negocio
--   LC_UNIT  → código de tienda
--   TYPE     → tipo de transacción (para filtros de net sales si aplica)
--   TYPEID   → identificador del tipo
--   AMOUNT   → monto monetario de la venta
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER VIEW [plh].[Vw_Vista_Venta_Neta]
AS
SELECT
    [LC_DOB],
    [LC_UNIT],
    [TYPE],
    [TYPEID],
    [AMOUNT]
FROM [ALOHA].[dbo].[GNDSALE];
GO
