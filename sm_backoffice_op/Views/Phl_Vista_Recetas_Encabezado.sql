SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE View [plh].[Phl_Vista_ProductosTerminados]
as
SELECT 
	     [Codigo_Receta]
      ,[NombreReceta]
      ,'UN' Unidad
      ,[DataAreaId]
  FROM [192.168.111.253].[BackOffice_SM].[dbo].[BO_Receta_Encabezado]
GO
