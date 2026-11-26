SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [plh].[Receta_detalle]
as
SELECT [ID_Detalle]
      ,[Id_Receta]
      ,[Codigo_Item]
      ,[Nombre_Item]
      ,[Cantidad_Item]
      ,[Unidad_Medida]
      ,[DataAreaID]
      ,[Cantidad_Estandar]
      ,[Unidad_Medida_Estandar]
      ,[Modificador]

  FROM [192.168.111.253].[BackOffice_SM].[dbo].[BO_Receta_Detalle_Ingredientes]
GO
