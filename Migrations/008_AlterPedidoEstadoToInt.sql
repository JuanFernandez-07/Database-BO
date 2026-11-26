-- =============================================
-- Migration 008 — ped_estado: NVARCHAR → TINYINT
-- 0 = PENDIENTE, 1 = ENVIADO, 2 = COMPLETADO, 3 = CANCELADO
-- =============================================

-- 1. Eliminar DEFAULT existente
DECLARE @cn NVARCHAR(200);
SELECT @cn = dc.name
FROM sys.default_constraints dc
INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina') AND c.name = 'ped_estado';
IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP CONSTRAINT [' + @cn + ']');
GO

-- 2. Agregar columna temporal
ALTER TABLE [plh].[plh_ped_pedidos_cocina] ADD [ped_estado_int] TINYINT NULL;
GO

-- 3. Convertir datos
UPDATE [plh].[plh_ped_pedidos_cocina]
SET [ped_estado_int] = CASE
    WHEN UPPER([ped_estado]) IN ('ENVIADO')               THEN 1
    WHEN UPPER([ped_estado]) IN ('COMPLETADO', 'RECIBIDO') THEN 2
    WHEN UPPER([ped_estado]) = 'CANCELADO'                THEN 3
    ELSE 0
END;
GO

-- 4. Eliminar columna original y renombrar
ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP COLUMN [ped_estado];
GO
EXEC sp_rename 'plh.plh_ped_pedidos_cocina.ped_estado_int', 'ped_estado', 'COLUMN';
GO

-- 5. NOT NULL + DEFAULT
ALTER TABLE [plh].[plh_ped_pedidos_cocina] ALTER COLUMN [ped_estado] TINYINT NOT NULL;
ALTER TABLE [plh].[plh_ped_pedidos_cocina] ADD CONSTRAINT [DF_ped_estado] DEFAULT 0 FOR [ped_estado];
GO
