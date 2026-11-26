SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER View [plh].[Phl_Vista_MateriaPrima]
as
SELECT 
	 [Codigo]
      ,[Nombre]
      ,[UnidadEstandar]
	  ,[DataAreaid]
      ,[Activo]
  FROM [192.168.111.253].[BackOffice_SM].[dbo].[BO_Mantenimiento_Inventario]
GO