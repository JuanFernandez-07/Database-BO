-- =============================================
-- Migration 007 — prh_estado_fermentacion: NVARCHAR → TINYINT
-- 0 = PENDIENTE, 1 = EN_FERMENTACION, 2 = FERMENTADO, 3 = COMPLETADO
-- =============================================

-- 1. Eliminar DEFAULT existente
DECLARE @cn NVARCHAR(200);
SELECT @cn = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND c.name = 'prh_estado_fermentacion';
IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [' + @cn + ']');
GO

-- 2. Agregar columna temporal
ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD [prh_estado_ferm_int] TINYINT NULL;
GO

-- 3. Convertir datos
UPDATE [plh].[plh_prh_proceso_horneado_encabezado]
SET [prh_estado_ferm_int] = CASE
    WHEN UPPER([prh_estado_fermentacion]) = 'EN_FERMENTACION' THEN 1
    WHEN UPPER([prh_estado_fermentacion]) = 'FERMENTADO'      THEN 2
    WHEN UPPER([prh_estado_fermentacion]) = 'COMPLETADO'      THEN 3
    ELSE 0
END;
GO

-- 4. Eliminar columna original y renombrar
ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP COLUMN [prh_estado_fermentacion];
GO
EXEC sp_rename 'plh.plh_prh_proceso_horneado_encabezado.prh_estado_ferm_int', 'prh_estado_fermentacion', 'COLUMN';
GO

-- 5. NOT NULL + DEFAULT
ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ALTER COLUMN [prh_estado_fermentacion] TINYINT NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD CONSTRAINT [DF_prh_estado_fermentacion] DEFAULT 0 FOR [prh_estado_fermentacion];
GO
