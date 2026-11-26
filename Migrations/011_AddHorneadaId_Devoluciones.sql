-- =============================================
-- Migration 011: Agrega horneadaId a la tabla de devoluciones
-- Requerimiento: La DEVO se registra por horneada (Horneada 1, 2, ..., N)
-- Script idempotente: seguro de re-ejecutar
-- =============================================

-- 1) Agregar columna solo si no existe
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_dev_devoluciones')
      AND name = 'dev_hor_id'
)
    ALTER TABLE plh.plh_dev_devoluciones
        ADD dev_hor_id BIGINT NULL;
GO

-- 2) Eliminar constraint única anterior (sin horneada) solo si existe
IF EXISTS (
    SELECT 1 FROM sys.key_constraints
    WHERE name = 'UQ_dev_fecha_tienda_producto'
      AND parent_object_id = OBJECT_ID('plh.plh_dev_devoluciones')
)
    ALTER TABLE plh.plh_dev_devoluciones DROP CONSTRAINT UQ_dev_fecha_tienda_producto;
GO

-- 3) Nuevo índice único que incluye horneada solo si no existe
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UQ_dev_fecha_tienda_producto_horneada'
      AND object_id = OBJECT_ID('plh.plh_dev_devoluciones')
)
    CREATE UNIQUE INDEX UQ_dev_fecha_tienda_producto_horneada
        ON plh.plh_dev_devoluciones (dev_fecha_venta, dev_tienda_codigo, dev_codigo_neg, dev_pro_codigo, dev_hor_id)
        WHERE dev_hor_id IS NOT NULL;
GO
