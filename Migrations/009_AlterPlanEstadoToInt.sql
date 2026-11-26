-- =============================================
-- Migration 009 — pla_estado: NVARCHAR → TINYINT
-- 0 = BORRADOR, 1 = ACTIVO, 2 = CERRADO
-- =============================================

-- 1. Eliminar DEFAULT existente
DECLARE @cn NVARCHAR(200);
SELECT @cn = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_pla_planes') AND c.name = 'pla_estado';
IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_pla_planes] DROP CONSTRAINT [' + @cn + ']');
GO

-- 2. Agregar columna temporal
ALTER TABLE [plh].[plh_pla_planes] ADD [pla_estado_int] TINYINT NULL;
GO

-- 3. Convertir datos
UPDATE [plh].[plh_pla_planes]
SET [pla_estado_int] = CASE
    WHEN UPPER([pla_estado]) = 'ACTIVO'  THEN 1
    WHEN UPPER([pla_estado]) = 'CERRADO' THEN 2
    ELSE 0
END;
GO

-- 4. Eliminar columna original y renombrar
ALTER TABLE [plh].[plh_pla_planes] DROP COLUMN [pla_estado];
GO
EXEC sp_rename 'plh.plh_pla_planes.pla_estado_int', 'pla_estado', 'COLUMN';
GO

-- 5. NOT NULL + DEFAULT
ALTER TABLE [plh].[plh_pla_planes] ALTER COLUMN [pla_estado] TINYINT NOT NULL;
ALTER TABLE [plh].[plh_pla_planes] ADD CONSTRAINT [DF_pla_estado] DEFAULT 0 FOR [pla_estado];
GO
