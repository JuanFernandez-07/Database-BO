SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [plh].[Vw_Vista_Venta_proyectada]
as
select negocio, tienda, fecha, venta_proyectada From 
 [SM_BO_DW].[PDS].[pds_ventas_proyectada]
GO
