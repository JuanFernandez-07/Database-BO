-- =============================================
-- Migration 005 — Cambiar dev_estado de NVARCHAR a TINYINT
-- Convención: 0 = PENDIENTE, 1 = AUTORIZADO
-- =============================================

-- 1. Eliminar la constraint DEFAULT existente (nombre generado automáticamente)
DECLARE @constraintName NVARCHAR(200);
SELECT @constraintName = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_dev_devoluciones')
  AND c.name = 'dev_estado';

IF @constraintName IS NOT NULL
    EXEC('ALTER TABLE [plh].[plh_dev_devoluciones] DROP CONSTRAINT [' + @constraintName + ']');
GO

-- 2. Agregar columna temporal TINYINT
ALTER TABLE [plh].[plh_dev_devoluciones]
    ADD [dev_estado_int] TINYINT NULL;
GO

-- 3. Copiar datos convertidos (batch separado para que SQL Server reconozca la nueva columna)
UPDATE [plh].[plh_dev_devoluciones]
SET [dev_estado_int] = CASE
    WHEN [dev_estado] = 'AUTORIZADO' THEN 1
    ELSE 0
END;
GO

-- 4. Eliminar columna string original
ALTER TABLE [plh].[plh_dev_devoluciones]
    DROP COLUMN [dev_estado];
GO

-- 5. Renombrar columna temporal al nombre definitivo
EXEC sp_rename 'plh.plh_dev_devoluciones.dev_estado_int', 'dev_estado', 'COLUMN';
GO

-- 6. Agregar NOT NULL y DEFAULT 0
ALTER TABLE [plh].[plh_dev_devoluciones]
    ALTER COLUMN [dev_estado] TINYINT NOT NULL;

ALTER TABLE [plh].[plh_dev_devoluciones]
    ADD CONSTRAINT [DF_dev_estado] DEFAULT 0 FOR [dev_estado];
GO
