SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE View [plh].[Phl_Vista_MateriaPrima]
as
select * from [SM_BO_DW].[PDS].[PDS_Inventario_Catalogo]
GO