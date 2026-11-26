-- =============================================
-- Migration 021: prc_estado_rotacion NVARCHAR → TINYINT
-- 0 = PENDIENTE, 1 = FINAL_CERRADO, 2 = CERRADO
-- Agrega prc_fecha_cierre_final y prc_usuario_cierre_final para el primer cierre
-- Idempotente: seguro de re-ejecutar
-- =============================================

USE [sm_backoffice_op];
GO

-- 1. Agregar columna TINYINT temporal
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_estado_rotacion_int'
)
    ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_estado_rotacion_int] TINYINT NULL;
GO

-- 2. Convertir datos existentes
UPDATE [plh].[plh_prc_procesos]
SET [prc_estado_rotacion_int] = CASE
    WHEN UPPER([prc_estado_rotacion]) = 'CERRADO'       THEN 2
    WHEN UPPER([prc_estado_rotacion]) = 'FINAL_CERRADO' THEN 1
    ELSE 0
END;
GO

-- 3. Eliminar DEFAULT existente en columna original
DECLARE @cn NVARCHAR(200);
SELECT @cn = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_prc_procesos') AND c.name = 'prc_estado_rotacion';
IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_prc_procesos] DROP CONSTRAINT [' + @cn + ']');
GO

-- 4. Eliminar columna original
ALTER TABLE [plh].[plh_prc_procesos] DROP COLUMN [prc_estado_rotacion];
GO

-- 5. Renombrar columna temporal
EXEC sp_rename 'plh.plh_prc_procesos.prc_estado_rotacion_int', 'prc_estado_rotacion', 'COLUMN';
GO

-- 6. NOT NULL + DEFAULT 0
ALTER TABLE [plh].[plh_prc_procesos] ALTER COLUMN [prc_estado_rotacion] TINYINT NOT NULL;
ALTER TABLE [plh].[plh_prc_procesos] ADD CONSTRAINT [DF_prc_estado_rotacion] DEFAULT 0 FOR [prc_estado_rotacion];
GO

-- 7. Agregar columnas de auditoría del cierre final
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_fecha_cierre_final'
)
    ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_fecha_cierre_final] DATETIME NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_usuario_cierre_final'
)
    ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_usuario_cierre_final] NVARCHAR(50) NULL;
GO
