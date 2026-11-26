-- Agrega columna hor_solo_productos_directos a plh_hor_horneadas.
-- Las horneadas marcadas con este flag solo aceptan productos sin fermentaci�n
-- (cat_requiere_fermentacion = 0 en el cat�logo).

USE [sm_backoffice_op];
GO

ALTER TABLE [plh].[plh_hor_horneadas]
ADD hor_solo_productos_directos BIT NOT NULL
    CONSTRAINT DF_hor_solo_productos_directos DEFAULT (0);
GO
