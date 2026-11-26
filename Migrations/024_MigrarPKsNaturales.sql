-- =============================================
-- Migration 024: Eliminar PKs surrogadas IDENTITY
--               Reemplazar por PKs naturales compuestas
-- Base: sm_backoffice_op
-- Idempotente: seguro de re-ejecutar
-- Requiere: migraciones 003–023 ya aplicadas
-- =============================================

USE [sm_backoffice_op];
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 0: DROP DINÁMICO de cualquier FK/índice sobre columnas surrogadas
--         que serán eliminadas. Busca por nombre de columna, NO por nombre
--         de constraint — cubre nombres generados automáticamente por SQL Server.
-- ══════════════════════════════════════════════════════════════════════════════

-- Helper: elimina todas las FKs de una tabla que referencien una columna dada
-- Se usa para prh_prc_id y prh_hor_id antes de drop column.

DECLARE @sql NVARCHAR(MAX) = N'';

-- FKs sobre plh_prh_proceso_horneado_encabezado.prh_prc_id
SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
  AND c.name = 'prh_prc_id';

-- FKs sobre plh_prh_proceso_horneado_encabezado.prh_hor_id
SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
  AND c.name = 'prh_hor_id';

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- Índices y unique constraints sobre plh_prh_proceso_horneado_encabezado
-- que incluyan prh_prc_id o prh_hor_id (cualquier nombre que tengan)
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql +
    CASE
        WHEN i.is_unique_constraint = 1 OR i.is_primary_key = 1
            THEN N'ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [' + i.name + N'];'
        ELSE N'DROP INDEX [' + i.name + N'] ON [plh].[plh_prh_proceso_horneado_encabezado];'
    END + CHAR(10)
FROM (
    SELECT DISTINCT i.name, i.is_unique_constraint, i.is_primary_key
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND c.name IN ('prh_prc_id', 'prh_hor_id', 'prh_id')
) i;

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs sobre plh_prh_proceso_horneado_detalle que referencien prh_id o prh_prh_id
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle')
  AND c.name IN ('prh_id', 'prh_prh_id');

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- Índices/PKs sobre plh_prh_proceso_horneado_detalle que incluyan prh_id o prh_prh_id
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql +
    CASE
        WHEN i.is_unique_constraint = 1 OR i.is_primary_key = 1
            THEN N'ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP CONSTRAINT [' + i.name + N'];'
        ELSE N'DROP INDEX [' + i.name + N'] ON [plh].[plh_prh_proceso_horneado_detalle];'
    END + CHAR(10)
FROM (
    SELECT DISTINCT i.name, i.is_unique_constraint, i.is_primary_key
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle')
      AND c.name IN ('prh_id', 'prh_prh_id')
) i;

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs sobre plh_trz_trazabilidad.trz_prh_id
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_trz_trazabilidad] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_trz_trazabilidad')
  AND c.name = 'trz_prh_id';

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs sobre plh_rot_rotacion.rot_hor_id
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_rot_rotacion] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_rot_rotacion')
  AND c.name = 'rot_hor_id';

-- Índices sobre plh_rot_rotacion que incluyan rot_hor_id
SELECT @sql = @sql +
    CASE
        WHEN i.is_unique_constraint = 1 OR i.is_primary_key = 1
            THEN N'ALTER TABLE [plh].[plh_rot_rotacion] DROP CONSTRAINT [' + i.name + N'];'
        ELSE N'DROP INDEX [' + i.name + N'] ON [plh].[plh_rot_rotacion];'
    END + CHAR(10)
FROM (
    SELECT DISTINCT i.name, i.is_unique_constraint, i.is_primary_key
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('plh.plh_rot_rotacion')
      AND c.name = 'rot_hor_id'
) i;

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs sobre plh_ped_pedidos_cocina.ped_hor_id
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina')
  AND c.name = 'ped_hor_id';

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs y UQs sobre plh_plh_plan_horneada (plh_hor_id, plh_pld_id, plh_id)
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada')
  AND c.name IN ('plh_hor_id', 'plh_pld_id');

SELECT @sql = @sql +
    CASE
        WHEN i.is_unique_constraint = 1 OR i.is_primary_key = 1
            THEN N'ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [' + i.name + N'];'
        ELSE N'DROP INDEX [' + i.name + N'] ON [plh].[plh_plh_plan_horneada];'
    END + CHAR(10)
FROM (
    SELECT DISTINCT i.name, i.is_unique_constraint, i.is_primary_key
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('plh.plh_plh_plan_horneada')
      AND c.name IN ('plh_id', 'plh_hor_id', 'plh_pld_id')
) i;

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- FKs y UQs sobre plh_pld_plan_detalle (pld_pla_id, pld_id)
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE [plh].[plh_pld_plan_detalle] DROP CONSTRAINT [' + fk.name + N'];' + CHAR(10)
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('plh.plh_pld_plan_detalle')
  AND c.name = 'pld_pla_id';

SELECT @sql = @sql +
    CASE
        WHEN i.is_unique_constraint = 1 OR i.is_primary_key = 1
            THEN N'ALTER TABLE [plh].[plh_pld_plan_detalle] DROP CONSTRAINT [' + i.name + N'];'
        ELSE N'DROP INDEX [' + i.name + N'] ON [plh].[plh_pld_plan_detalle];'
    END + CHAR(10)
FROM (
    SELECT DISTINCT i.name, i.is_unique_constraint, i.is_primary_key
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('plh.plh_pld_plan_detalle')
      AND c.name IN ('pld_id', 'pld_pla_id')
) i;

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- PKs surrogadas de todas las tablas afectadas (por nombre — ya probados)
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql +
    N'ALTER TABLE [' + SCHEMA_NAME(t.schema_id) + N'].[' + t.name + N'] DROP CONSTRAINT [' + k.name + N'];' + CHAR(10)
FROM sys.key_constraints k
JOIN sys.tables t ON t.object_id = k.parent_object_id
WHERE k.type = 'PK'
  AND t.schema_id = SCHEMA_ID('plh')
  AND k.name IN (
    'PK_hor','PK_log','PK_cat','PK_mrf','PK_pla','PK_pld',
    'PK_plh','PK_ped','PK_prc','PK_prh_enc','PK_prh_det'
  );

IF LEN(@sql) > 0 EXEC sp_executesql @sql;
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 1: DROP FKs por nombre (redundante con FASE 0 pero inocuo si ya cayeron)
-- ══════════════════════════════════════════════════════════════════════════════

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_trz_prh'
           AND parent_object_id = OBJECT_ID('plh.plh_trz_trazabilidad'))
    ALTER TABLE [plh].[plh_trz_trazabilidad] DROP CONSTRAINT [FK_trz_prh];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_rot_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    ALTER TABLE [plh].[plh_rot_rotacion] DROP CONSTRAINT [FK_rot_hor];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_det_enc'
           AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP CONSTRAINT [FK_prh_det_enc];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_prc'
           AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [FK_prh_prc];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [FK_prh_hor];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ped_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina'))
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP CONSTRAINT [FK_ped_hor];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_plh_pld'
           AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [FK_plh_pld];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_plh_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [FK_plh_hor];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pld_pla'
           AND parent_object_id = OBJECT_ID('plh.plh_pld_plan_detalle'))
    ALTER TABLE [plh].[plh_pld_plan_detalle] DROP CONSTRAINT [FK_pld_pla];
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_log_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_log_parametrizacion'))
    ALTER TABLE [plh].[plh_log_parametrizacion] DROP CONSTRAINT [FK_log_hor];
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 2: DROP UNIQUE constraints / índices por nombre
--         (redundante con FASE 0 para los que tienen nombre conocido)
-- ══════════════════════════════════════════════════════════════════════════════

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_hor_tienda_secuencia'
           AND object_id = OBJECT_ID('plh.plh_hor_horneadas'))
    ALTER TABLE [plh].[plh_hor_horneadas] DROP CONSTRAINT [UQ_hor_tienda_secuencia];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_cat_tienda_producto'
           AND object_id = OBJECT_ID('plh.plh_cat_catalogo_productos'))
    ALTER TABLE [plh].[plh_cat_catalogo_productos] DROP CONSTRAINT [UQ_cat_tienda_producto];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_mrf_codigo_neg_anio_mes'
           AND object_id = OBJECT_ID('plh.plh_mrf_mes_referencia'))
    ALTER TABLE [plh].[plh_mrf_mes_referencia] DROP CONSTRAINT [UQ_mrf_codigo_neg_anio_mes];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_pla_fecha_tienda'
           AND object_id = OBJECT_ID('plh.plh_pla_planes'))
    ALTER TABLE [plh].[plh_pla_planes] DROP CONSTRAINT [UQ_pla_fecha_tienda];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_prc_fecha_tienda'
           AND object_id = OBJECT_ID('plh.plh_prc_procesos'))
    ALTER TABLE [plh].[plh_prc_procesos] DROP CONSTRAINT [UQ_prc_fecha_tienda];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_pld_plan_producto'
           AND object_id = OBJECT_ID('plh.plh_pld_plan_detalle'))
    ALTER TABLE [plh].[plh_pld_plan_detalle] DROP CONSTRAINT [UQ_pld_plan_producto];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_plh_detalle_horneada'
           AND object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [UQ_plh_detalle_horneada];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_ped_fecha_tienda_producto_horneada'
           AND object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina'))
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP CONSTRAINT [UQ_ped_fecha_tienda_producto_horneada];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_prh_proceso_producto_horneada'
           AND object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [UQ_prh_proceso_producto_horneada];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_rot_fecha_tienda_producto_horneada'
           AND object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    DROP INDEX [UQ_rot_fecha_tienda_producto_horneada] ON [plh].[plh_rot_rotacion];
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rot_transferencias'
           AND object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    DROP INDEX [IX_rot_transferencias] ON [plh].[plh_rot_rotacion];
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 3: DROP PKs surrogadas (redundante con FASE 0 pero inocuo)
-- ══════════════════════════════════════════════════════════════════════════════

IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_hor'
           AND parent_object_id = OBJECT_ID('plh.plh_hor_horneadas'))
    ALTER TABLE [plh].[plh_hor_horneadas] DROP CONSTRAINT [PK_hor];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_log'
           AND parent_object_id = OBJECT_ID('plh.plh_log_parametrizacion'))
    ALTER TABLE [plh].[plh_log_parametrizacion] DROP CONSTRAINT [PK_log];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_cat'
           AND parent_object_id = OBJECT_ID('plh.plh_cat_catalogo_productos'))
    ALTER TABLE [plh].[plh_cat_catalogo_productos] DROP CONSTRAINT [PK_cat];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_mrf'
           AND parent_object_id = OBJECT_ID('plh.plh_mrf_mes_referencia'))
    ALTER TABLE [plh].[plh_mrf_mes_referencia] DROP CONSTRAINT [PK_mrf];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_pla'
           AND parent_object_id = OBJECT_ID('plh.plh_pla_planes'))
    ALTER TABLE [plh].[plh_pla_planes] DROP CONSTRAINT [PK_pla];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_pld'
           AND parent_object_id = OBJECT_ID('plh.plh_pld_plan_detalle'))
    ALTER TABLE [plh].[plh_pld_plan_detalle] DROP CONSTRAINT [PK_pld];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_plh'
           AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP CONSTRAINT [PK_plh];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_ped'
           AND parent_object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina'))
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP CONSTRAINT [PK_ped];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prc'
           AND parent_object_id = OBJECT_ID('plh.plh_prc_procesos'))
    ALTER TABLE [plh].[plh_prc_procesos] DROP CONSTRAINT [PK_prc];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prh_enc'
           AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP CONSTRAINT [PK_prh_enc];
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prh_det'
           AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP CONSTRAINT [PK_prh_det];
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 4: Agregar columnas de clave natural en tablas hijo
--         (todas como NULL primero, luego poblar, luego NOT NULL)
-- ══════════════════════════════════════════════════════════════════════════════

-- ─── plh_pld_plan_detalle ────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pld_plan_detalle') AND name = 'pld_codigo_neg')
    ALTER TABLE [plh].[plh_pld_plan_detalle] ADD [pld_codigo_neg] NVARCHAR(10) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pld_plan_detalle') AND name = 'pld_tienda_codigo')
    ALTER TABLE [plh].[plh_pld_plan_detalle] ADD [pld_tienda_codigo] INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pld_plan_detalle') AND name = 'pld_fecha')
    ALTER TABLE [plh].[plh_pld_plan_detalle] ADD [pld_fecha] DATE NULL;
GO

UPDATE pld
SET pld_codigo_neg    = pla.pla_codigo_neg,
    pld_tienda_codigo = pla.pla_tienda_codigo,
    pld_fecha         = pla.pla_fecha
FROM [plh].[plh_pld_plan_detalle] pld
INNER JOIN [plh].[plh_pla_planes] pla ON pla.pla_id = pld.pld_pla_id
WHERE pld.pld_codigo_neg IS NULL;
GO

ALTER TABLE [plh].[plh_pld_plan_detalle] ALTER COLUMN [pld_codigo_neg]   NVARCHAR(10) NOT NULL;
ALTER TABLE [plh].[plh_pld_plan_detalle] ALTER COLUMN [pld_tienda_codigo] INT NOT NULL;
ALTER TABLE [plh].[plh_pld_plan_detalle] ALTER COLUMN [pld_fecha]        DATE NOT NULL;
GO

-- ─── plh_plh_plan_horneada ───────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_codigo_neg')
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD [plh_codigo_neg] NVARCHAR(10) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_tienda_codigo')
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD [plh_tienda_codigo] INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_fecha')
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD [plh_fecha] DATE NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_pro_codigo')
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD [plh_pro_codigo] NVARCHAR(50) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD [plh_hor_numero_secuencia] INT NULL;
GO

UPDATE ph
SET plh_codigo_neg           = pla.pla_codigo_neg,
    plh_tienda_codigo        = pla.pla_tienda_codigo,
    plh_fecha                = pla.pla_fecha,
    plh_pro_codigo           = pld.pld_pro_codigo,
    plh_hor_numero_secuencia = hor.hor_numero_secuencia
FROM [plh].[plh_plh_plan_horneada] ph
INNER JOIN [plh].[plh_pld_plan_detalle] pld ON pld.pld_id = ph.plh_pld_id
INNER JOIN [plh].[plh_pla_planes]       pla ON pla.pla_id = pld.pld_pla_id
INNER JOIN [plh].[plh_hor_horneadas]    hor ON hor.hor_id = ph.plh_hor_id
WHERE ph.plh_codigo_neg IS NULL;
GO

ALTER TABLE [plh].[plh_plh_plan_horneada] ALTER COLUMN [plh_codigo_neg]           NVARCHAR(10) NOT NULL;
ALTER TABLE [plh].[plh_plh_plan_horneada] ALTER COLUMN [plh_tienda_codigo]         INT NOT NULL;
ALTER TABLE [plh].[plh_plh_plan_horneada] ALTER COLUMN [plh_fecha]                DATE NOT NULL;
ALTER TABLE [plh].[plh_plh_plan_horneada] ALTER COLUMN [plh_pro_codigo]            NVARCHAR(50) NOT NULL;
ALTER TABLE [plh].[plh_plh_plan_horneada] ALTER COLUMN [plh_hor_numero_secuencia]  INT NOT NULL;
GO

-- ─── plh_ped_pedidos_cocina ──────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina') AND name = 'ped_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] ADD [ped_hor_numero_secuencia] INT NULL;
GO

UPDATE ped
SET ped_hor_numero_secuencia = hor.hor_numero_secuencia
FROM [plh].[plh_ped_pedidos_cocina] ped
INNER JOIN [plh].[plh_hor_horneadas] hor ON hor.hor_id = ped.ped_hor_id
WHERE ped.ped_hor_numero_secuencia IS NULL;
GO

ALTER TABLE [plh].[plh_ped_pedidos_cocina] ALTER COLUMN [ped_hor_numero_secuencia] INT NOT NULL;
GO

-- ─── plh_prh_proceso_horneado_encabezado ────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_fecha')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD [prh_fecha] DATE NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD [prh_hor_numero_secuencia] INT NULL;
GO

UPDATE enc
SET prh_fecha                = prc.prc_fecha,
    prh_hor_numero_secuencia = hor.hor_numero_secuencia
FROM [plh].[plh_prh_proceso_horneado_encabezado] enc
INNER JOIN [plh].[plh_prc_procesos]  prc ON prc.prc_id = enc.prh_prc_id
INNER JOIN [plh].[plh_hor_horneadas] hor ON hor.hor_id = enc.prh_hor_id
WHERE enc.prh_fecha IS NULL;
GO

ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ALTER COLUMN [prh_fecha]                DATE NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ALTER COLUMN [prh_hor_numero_secuencia] INT  NOT NULL;
GO

-- ─── plh_prh_proceso_horneado_detalle ───────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_codigo_neg')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD [prh_codigo_neg] NVARCHAR(10) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_tienda_codigo')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD [prh_tienda_codigo] INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_fecha')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD [prh_fecha] DATE NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_pro_codigo')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD [prh_pro_codigo] NVARCHAR(50) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD [prh_hor_numero_secuencia] INT NULL;
GO

UPDATE det
SET prh_codigo_neg           = enc.prh_codigo_neg,
    prh_tienda_codigo        = enc.prh_tienda_codigo,
    prh_fecha                = enc.prh_fecha,
    prh_pro_codigo           = enc.prh_pro_codigo,
    prh_hor_numero_secuencia = enc.prh_hor_numero_secuencia
FROM [plh].[plh_prh_proceso_horneado_detalle] det
INNER JOIN [plh].[plh_prh_proceso_horneado_encabezado] enc ON enc.prh_id = det.prh_prh_id
WHERE det.prh_codigo_neg IS NULL;
GO

ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ALTER COLUMN [prh_codigo_neg]           NVARCHAR(10) NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ALTER COLUMN [prh_tienda_codigo]         INT NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ALTER COLUMN [prh_fecha]                DATE NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ALTER COLUMN [prh_pro_codigo]            NVARCHAR(50) NOT NULL;
ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ALTER COLUMN [prh_hor_numero_secuencia]  INT NOT NULL;
GO

-- ─── plh_trz_trazabilidad ───────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_codigo_neg')
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_prh_codigo_neg] NVARCHAR(10) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_tienda_codigo')
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_prh_tienda_codigo] INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_fecha')
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_prh_fecha] DATE NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_pro_codigo')
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_prh_pro_codigo] NVARCHAR(50) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_prh_hor_numero_secuencia] INT NULL;
GO

UPDATE trz
SET trz_prh_codigo_neg           = enc.prh_codigo_neg,
    trz_prh_tienda_codigo        = enc.prh_tienda_codigo,
    trz_prh_fecha                = enc.prh_fecha,
    trz_prh_pro_codigo           = enc.prh_pro_codigo,
    trz_prh_hor_numero_secuencia = enc.prh_hor_numero_secuencia
FROM [plh].[plh_trz_trazabilidad] trz
INNER JOIN [plh].[plh_prh_proceso_horneado_encabezado] enc ON enc.prh_id = trz.trz_prh_id
WHERE trz.trz_prh_codigo_neg IS NULL;
GO

ALTER TABLE [plh].[plh_trz_trazabilidad] ALTER COLUMN [trz_prh_codigo_neg]           NVARCHAR(10) NOT NULL;
ALTER TABLE [plh].[plh_trz_trazabilidad] ALTER COLUMN [trz_prh_tienda_codigo]         INT NOT NULL;
ALTER TABLE [plh].[plh_trz_trazabilidad] ALTER COLUMN [trz_prh_fecha]                DATE NOT NULL;
ALTER TABLE [plh].[plh_trz_trazabilidad] ALTER COLUMN [trz_prh_pro_codigo]            NVARCHAR(50) NOT NULL;
ALTER TABLE [plh].[plh_trz_trazabilidad] ALTER COLUMN [trz_prh_hor_numero_secuencia]  INT NOT NULL;
GO

-- ─── plh_log_parametrizacion ────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_log_parametrizacion') AND name = 'log_codigo_neg')
    ALTER TABLE [plh].[plh_log_parametrizacion] ADD [log_codigo_neg] NVARCHAR(10) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_log_parametrizacion') AND name = 'log_tienda_codigo')
    ALTER TABLE [plh].[plh_log_parametrizacion] ADD [log_tienda_codigo] INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_log_parametrizacion') AND name = 'log_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_log_parametrizacion] ADD [log_hor_numero_secuencia] INT NULL;
GO

UPDATE lg
SET log_codigo_neg           = hor.hor_codigo_neg,
    log_tienda_codigo        = hor.hor_tienda_codigo,
    log_hor_numero_secuencia = hor.hor_numero_secuencia
FROM [plh].[plh_log_parametrizacion] lg
INNER JOIN [plh].[plh_hor_horneadas] hor ON hor.hor_id = lg.log_hor_id
WHERE lg.log_codigo_neg IS NULL;
GO

ALTER TABLE [plh].[plh_log_parametrizacion] ALTER COLUMN [log_codigo_neg]           NVARCHAR(10) NOT NULL;
ALTER TABLE [plh].[plh_log_parametrizacion] ALTER COLUMN [log_tienda_codigo]         INT NOT NULL;
ALTER TABLE [plh].[plh_log_parametrizacion] ALTER COLUMN [log_hor_numero_secuencia]  INT NOT NULL;
GO

-- ─── plh_rot_rotacion ───────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'rot_hor_numero_secuencia')
    ALTER TABLE [plh].[plh_rot_rotacion] ADD [rot_hor_numero_secuencia] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'rot_es_transferencia')
    ALTER TABLE [plh].[plh_rot_rotacion] ADD [rot_es_transferencia] BIT NOT NULL CONSTRAINT [DF_rot_es_transferencia] DEFAULT (0);
GO

UPDATE rot
SET rot_hor_numero_secuencia = hor.hor_numero_secuencia
FROM [plh].[plh_rot_rotacion] rot
INNER JOIN [plh].[plh_hor_horneadas] hor ON hor.hor_id = rot.rot_hor_id
WHERE rot.rot_hor_numero_secuencia IS NULL AND rot.rot_hor_id IS NOT NULL;
GO

-- ─── plh_prc_procesos: columnas nuevas del schema final ─────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_fecha_cierre_final')
    ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_fecha_cierre_final] DATETIME NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_usuario_cierre_final')
    ALTER TABLE [plh].[plh_prc_procesos] ADD [prc_usuario_cierre_final] NVARCHAR(50) NULL;
GO

-- ─── plh_pla_planes: pla_fecha_comparacion debe ser NULL ────────────────────
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_pla_planes') AND name = 'pla_fecha_comparacion' AND is_nullable = 0
)
    ALTER TABLE [plh].[plh_pla_planes] ALTER COLUMN [pla_fecha_comparacion] DATE NULL;
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 5: DROP columnas surrogadas
--         A este punto FASE 0 ya limpió todas las dependencias — estos son
--         seguros de correr aunque queden residuos con nombres inesperados.
-- ══════════════════════════════════════════════════════════════════════════════

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_hor_horneadas') AND name = 'hor_id')
    ALTER TABLE [plh].[plh_hor_horneadas] DROP COLUMN [hor_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_log_parametrizacion') AND name = 'log_id')
    ALTER TABLE [plh].[plh_log_parametrizacion] DROP COLUMN [log_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_log_parametrizacion') AND name = 'log_hor_id')
    ALTER TABLE [plh].[plh_log_parametrizacion] DROP COLUMN [log_hor_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_id')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] DROP COLUMN [cat_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_mrf_mes_referencia') AND name = 'mrf_id')
    ALTER TABLE [plh].[plh_mrf_mes_referencia] DROP COLUMN [mrf_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pla_planes') AND name = 'pla_id')
    ALTER TABLE [plh].[plh_pla_planes] DROP COLUMN [pla_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pld_plan_detalle') AND name = 'pld_id')
    ALTER TABLE [plh].[plh_pld_plan_detalle] DROP COLUMN [pld_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_pld_plan_detalle') AND name = 'pld_pla_id')
    ALTER TABLE [plh].[plh_pld_plan_detalle] DROP COLUMN [pld_pla_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_id')
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP COLUMN [plh_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_pld_id')
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP COLUMN [plh_pld_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_plh_plan_horneada') AND name = 'plh_hor_id')
    ALTER TABLE [plh].[plh_plh_plan_horneada] DROP COLUMN [plh_hor_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina') AND name = 'ped_id')
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP COLUMN [ped_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina') AND name = 'ped_hor_id')
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] DROP COLUMN [ped_hor_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prc_procesos') AND name = 'prc_id')
    ALTER TABLE [plh].[plh_prc_procesos] DROP COLUMN [prc_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_id')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP COLUMN [prh_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_prc_id')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP COLUMN [prh_prc_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_hor_id')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] DROP COLUMN [prh_hor_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_id')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP COLUMN [prh_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle') AND name = 'prh_prh_id')
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] DROP COLUMN [prh_prh_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_prh_id')
    ALTER TABLE [plh].[plh_trz_trazabilidad] DROP COLUMN [trz_prh_id];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'rot_hor_id')
    ALTER TABLE [plh].[plh_rot_rotacion] DROP COLUMN [rot_hor_id];
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 6: Crear nuevas PKs compuestas
-- ══════════════════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_hor' AND parent_object_id = OBJECT_ID('plh.plh_hor_horneadas'))
    ALTER TABLE [plh].[plh_hor_horneadas] ADD CONSTRAINT [PK_hor]
        PRIMARY KEY (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_log' AND parent_object_id = OBJECT_ID('plh.plh_log_parametrizacion'))
    ALTER TABLE [plh].[plh_log_parametrizacion] ADD CONSTRAINT [PK_log]
        PRIMARY KEY (log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia, log_fecha_hora, log_campo_modificado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_cat' AND parent_object_id = OBJECT_ID('plh.plh_cat_catalogo_productos'))
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD CONSTRAINT [PK_cat]
        PRIMARY KEY (cat_codigo_neg, cat_tienda_codigo, cat_pro_codigo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_mrf' AND parent_object_id = OBJECT_ID('plh.plh_mrf_mes_referencia'))
    ALTER TABLE [plh].[plh_mrf_mes_referencia] ADD CONSTRAINT [PK_mrf]
        PRIMARY KEY (mrf_codigo_neg, mrf_anio, mrf_mes);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_pla' AND parent_object_id = OBJECT_ID('plh.plh_pla_planes'))
    ALTER TABLE [plh].[plh_pla_planes] ADD CONSTRAINT [PK_pla]
        PRIMARY KEY (pla_codigo_neg, pla_tienda_codigo, pla_fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_pld' AND parent_object_id = OBJECT_ID('plh.plh_pld_plan_detalle'))
    ALTER TABLE [plh].[plh_pld_plan_detalle] ADD CONSTRAINT [PK_pld]
        PRIMARY KEY (pld_codigo_neg, pld_tienda_codigo, pld_fecha, pld_pro_codigo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_plh' AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD CONSTRAINT [PK_plh]
        PRIMARY KEY (plh_codigo_neg, plh_tienda_codigo, plh_fecha, plh_pro_codigo, plh_hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_ped' AND parent_object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina'))
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] ADD CONSTRAINT [PK_ped]
        PRIMARY KEY (ped_codigo_neg, ped_tienda_codigo, ped_fecha, ped_pro_codigo, ped_hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prc' AND parent_object_id = OBJECT_ID('plh.plh_prc_procesos'))
    ALTER TABLE [plh].[plh_prc_procesos] ADD CONSTRAINT [PK_prc]
        PRIMARY KEY (prc_codigo_neg, prc_tienda_codigo, prc_fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prh_enc' AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD CONSTRAINT [PK_prh_enc]
        PRIMARY KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_prh_det' AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD CONSTRAINT [PK_prh_det]
        PRIMARY KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia);
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 7: Crear nuevas FKs compuestas
-- ══════════════════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_log_hor' AND parent_object_id = OBJECT_ID('plh.plh_log_parametrizacion'))
    ALTER TABLE [plh].[plh_log_parametrizacion] ADD CONSTRAINT [FK_log_hor]
        FOREIGN KEY (log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pld_pla' AND parent_object_id = OBJECT_ID('plh.plh_pld_plan_detalle'))
    ALTER TABLE [plh].[plh_pld_plan_detalle] ADD CONSTRAINT [FK_pld_pla]
        FOREIGN KEY (pld_codigo_neg, pld_tienda_codigo, pld_fecha)
        REFERENCES [plh].[plh_pla_planes] (pla_codigo_neg, pla_tienda_codigo, pla_fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_plh_pld' AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD CONSTRAINT [FK_plh_pld]
        FOREIGN KEY (plh_codigo_neg, plh_tienda_codigo, plh_fecha, plh_pro_codigo)
        REFERENCES [plh].[plh_pld_plan_detalle] (pld_codigo_neg, pld_tienda_codigo, pld_fecha, pld_pro_codigo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_plh_hor' AND parent_object_id = OBJECT_ID('plh.plh_plh_plan_horneada'))
    ALTER TABLE [plh].[plh_plh_plan_horneada] ADD CONSTRAINT [FK_plh_hor]
        FOREIGN KEY (plh_codigo_neg, plh_tienda_codigo, plh_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ped_hor' AND parent_object_id = OBJECT_ID('plh.plh_ped_pedidos_cocina'))
    ALTER TABLE [plh].[plh_ped_pedidos_cocina] ADD CONSTRAINT [FK_ped_hor]
        FOREIGN KEY (ped_codigo_neg, ped_tienda_codigo, ped_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_prc' AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD CONSTRAINT [FK_prh_prc]
        FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha)
        REFERENCES [plh].[plh_prc_procesos] (prc_codigo_neg, prc_tienda_codigo, prc_fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_hor' AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado] ADD CONSTRAINT [FK_prh_hor]
        FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_det_enc' AND parent_object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle'))
    ALTER TABLE [plh].[plh_prh_proceso_horneado_detalle] ADD CONSTRAINT [FK_prh_det_enc]
        FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_prh_proceso_horneado_encabezado] (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_trz_prh' AND parent_object_id = OBJECT_ID('plh.plh_trz_trazabilidad'))
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD CONSTRAINT [FK_trz_prh]
        FOREIGN KEY (trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha, trz_prh_pro_codigo, trz_prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_prh_proceso_horneado_encabezado] (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_rot_hor' AND parent_object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    ALTER TABLE [plh].[plh_rot_rotacion] ADD CONSTRAINT [FK_rot_hor]
        FOREIGN KEY (rot_codigo_neg, rot_tienda_codigo, rot_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia);
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- FASE 8: Recrear índices de rot_rotacion
-- ══════════════════════════════════════════════════════════════════════════════

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_rot_fecha_tienda_producto_horneada' AND object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    CREATE UNIQUE INDEX [UQ_rot_fecha_tienda_producto_horneada]
        ON [plh].[plh_rot_rotacion] (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_pro_codigo, rot_hor_numero_secuencia)
        WHERE rot_hor_numero_secuencia IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rot_transferencias' AND object_id = OBJECT_ID('plh.plh_rot_rotacion'))
    CREATE INDEX [IX_rot_transferencias]
        ON [plh].[plh_rot_rotacion] (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_es_transferencia)
        WHERE rot_es_transferencia = 1;
GO

-- ══════════════════════════════════════════════════════════════════════════════
-- POST-MIGRACIÓN: re-ejecutar todos los SPs
--   StoredProceduresFinal/01_Horneadas.sql
--   StoredProceduresFinal/02_Catalogo.sql
--   StoredProceduresFinal/03_Plan.sql
--   StoredProceduresFinal/04_Proceso.sql
--   StoredProceduresFinal/05_PedidoCocina.sql
--   StoredProceduresFinal/06_ControlReposteria.sql
--   StoredProceduresFinal/07_Devolucion.sql
--   StoredProceduresFinal/08_MotorCalculo.sql
--   StoredProceduresFinal/09_Funciones.sql
-- ══════════════════════════════════════════════════════════════════════════════
