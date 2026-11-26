-- =============================================
-- Migration 015: Ajustes a tabla de devoluciones para nuevo modelo
-- Requerimiento: La DEVO se registra múltiples veces por día por producto (sin distinción de horneada).
--                Al final del día se hace cierre para bloquear modificaciones.
-- Script idempotente: seguro de re-ejecutar
-- =============================================

-- 1) Agregar campo cierre de día
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_dev_devoluciones')
      AND name = 'dev_dia_cerrado'
)
    ALTER TABLE plh.plh_dev_devoluciones
        ADD dev_dia_cerrado BIT NOT NULL CONSTRAINT DF_dev_dia_cerrado DEFAULT (0);
GO

-- 2) Eliminar índice único por producto+horneada (ya no aplica: múltiples entradas por producto/día)
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UQ_dev_fecha_tienda_producto_horneada'
      AND object_id = OBJECT_ID('plh.plh_dev_devoluciones')
)
    DROP INDEX UQ_dev_fecha_tienda_producto_horneada ON plh.plh_dev_devoluciones;
GO

-- 3) Hacer dev_hor_id nullable si aún no lo es (ya debería ser NULL desde migration 011)
-- (no requiere ALTER: la columna ya es NULL desde migration 011)
