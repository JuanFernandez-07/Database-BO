-- ============================================================
-- Migración 016 — CR Hornos: nuevos campos en proceso y rotación
-- Ejecutar en sm_backoffice_op (entorno de desarrollo/test)
-- Idempotente: puede correrse múltiples veces sin error.
-- ============================================================

-- ──────────────────────────────────────────────
-- 1. plh_prh_proceso_horneado_encabezado
-- ──────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_omitio_fermentacion')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_omitio_fermentacion BIT NOT NULL DEFAULT 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_temperatura_descongelamiento')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_temperatura_descongelamiento DECIMAL(5,1) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_temperatura_2')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_temperatura_2 DECIMAL(5,1) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_temperatura_3')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_temperatura_3 DECIMAL(5,1) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_temperatura_4')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_temperatura_4 DECIMAL(5,1) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado') AND name = 'prh_vapor_segundos')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD prh_vapor_segundos INT NULL;
GO

-- ──────────────────────────────────────────────
-- 2. plh_rot_rotacion
--    a) Agregar rot_es_transferencia
--    b) Hacer rot_hor_id nullable
--    c) Recrear índice único filtrado
-- ──────────────────────────────────────────────

-- a) Nueva columna
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'rot_es_transferencia')
    ALTER TABLE plh.plh_rot_rotacion ADD rot_es_transferencia BIT NOT NULL DEFAULT 0;
GO

-- b) Quitar restricción única existente (puede ser CONSTRAINT o INDEX según el entorno)
IF EXISTS (
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('plh.plh_rot_rotacion')
      AND name = 'UQ_rot_fecha_tienda_producto_horneada'
      AND type = 'UQ'
)
    ALTER TABLE plh.plh_rot_rotacion DROP CONSTRAINT UQ_rot_fecha_tienda_producto_horneada;
GO
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion')
      AND name = 'UQ_rot_fecha_tienda_producto_horneada'
      AND is_unique_constraint = 0
)
    DROP INDEX UQ_rot_fecha_tienda_producto_horneada ON plh.plh_rot_rotacion;
GO

-- c) Hacer nullable rot_hor_id
ALTER TABLE plh.plh_rot_rotacion
    ALTER COLUMN rot_hor_id BIGINT NULL;
GO

-- d) Recrear como índice filtrado
--    Registros normales: unicidad por fecha+tienda+neg+producto+horneada
--    Transferencias (rot_hor_id NULL): SQL Server permite múltiples NULLs en índice filtrado
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'UQ_rot_fecha_tienda_producto_horneada')
    CREATE UNIQUE INDEX UQ_rot_fecha_tienda_producto_horneada
        ON plh.plh_rot_rotacion (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_pro_codigo, rot_hor_id)
        WHERE rot_hor_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('plh.plh_rot_rotacion') AND name = 'IX_rot_transferencias')
    CREATE INDEX IX_rot_transferencias
        ON plh.plh_rot_rotacion (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_es_transferencia)
        WHERE rot_es_transferencia = 1;
GO
