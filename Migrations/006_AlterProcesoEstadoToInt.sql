-- =============================================
-- Migration 006 — prc_estado: NVARCHAR → TINYINT
-- 0 = PENDIENTE, 1 = EN_PROCESO, 2 = FINALIZADO
-- =============================================

-- 1. Eliminar DEFAULT existente
DECLARE @cn NVARCHAR(200);
SELECT @cn = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_prc_procesos') AND c.name = 'prc_estado';
IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_prc_procesos] DROP CONSTRAINT [' + @cn + ']');
GO

-- 2. Agregar columna temporal
ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_estado_int] TINYINT NULL;
GO

-- 3. Convertir datos
UPDATE [plh].[plh_prc_procesos]
SET [prc_estado_int] = CASE
    WHEN UPPER([prc_estado]) = 'EN_PROCESO'  THEN 1
    WHEN UPPER([prc_estado]) = 'FINALIZADO'  THEN 2
    ELSE 0
END;
GO

-- 4. Eliminar columna original y renombrar
ALTER TABLE [plh].[plh_prc_procesos] DROP COLUMN [prc_estado];
GO
EXEC sp_rename 'plh.plh_prc_procesos.prc_estado_int', 'prc_estado', 'COLUMN';
GO

-- 5. NOT NULL + DEFAULT
ALTER TABLE [plh].[plh_prc_procesos] ALTER COLUMN [prc_estado] TINYINT NOT NULL;
ALTER TABLE [plh].[plh_prc_procesos] ADD CONSTRAINT [DF_prc_estado] DEFAULT 0 FOR [prc_estado];
GO
