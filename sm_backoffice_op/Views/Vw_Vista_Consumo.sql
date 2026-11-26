SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE view [plh].[Vw_Vista_Consumo]

as

SELECT 
	   [LC_DOB]
      ,[LC_UNIT]
	  ,[ITEM]
	  ,[BOHNAME]
	  ,[QUANTITY] Cantidad
	  ,[HOUR]
  FROM [ALOHA].[dbo].[GNDITEM]
 
GO