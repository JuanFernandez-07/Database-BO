-- CR-20260922-01 (Fase 2, HORNOS-F2-FRAC) — Fracciones de bolsa múltiples.
-- Se sigue usando la misma columna cat_fraccion_bolsa (sin tabla nueva): cambia de
-- DECIMAL(4,2) a NVARCHAR(20) y pasa a guardar una lista separada por coma
-- (ej. "0.25,0.5") en vez de un solo valor — un producto puede tener una o más
-- fracciones habilitadas simultáneamente.
--
-- Los valores existentes migran solos: ALTER COLUMN convierte cada decimal ya
-- guardado a su representación en texto (ej. 1.00 -> '1.00'), que se sigue leyendo
-- como lista de un solo elemento sin pérdida de datos.

USE [sm_backoffice_op];
GO

-- El DEFAULT de cat_fraccion_bolsa puede existir con nombre autogenerado
-- (ej. DF__plh_cat_c__cat_f__xxxxxxxx) en vez de DF_cat_fraccion_bolsa si la
-- columna se creó sin nombre explícito de constraint — se busca dinámicamente
-- en vez de asumir un nombre fijo.
DECLARE @ConstraintName SYSNAME;
SELECT @ConstraintName = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c
        ON c.object_id = dc.parent_object_id
       AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('plh.plh_cat_catalogo_productos')
  AND c.name = 'cat_fraccion_bolsa';

IF @ConstraintName IS NOT NULL
BEGIN
    EXEC('ALTER TABLE [plh].[plh_cat_catalogo_productos] DROP CONSTRAINT [' + @ConstraintName + ']');
END
GO

ALTER TABLE [plh].[plh_cat_catalogo_productos]
ALTER COLUMN cat_fraccion_bolsa NVARCHAR(20) NOT NULL;
GO

ALTER TABLE [plh].[plh_cat_catalogo_productos]
ADD CONSTRAINT DF_cat_fraccion_bolsa DEFAULT ('1.00') FOR cat_fraccion_bolsa;
GO
