SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE view [plh].[plh_Vw_VentaDiaria]
as
select 
 [negocio]
      ,[tienda]
      ,[codigo_producto]
      ,[fecha]
      ,[venta_diaria]
      ,[fecha_carga]
      ,[cantidad_diaria]
	 ,[nombre]
From [SM_BO_DW].[PDS].[pds_ventas_pedidos]
GO
