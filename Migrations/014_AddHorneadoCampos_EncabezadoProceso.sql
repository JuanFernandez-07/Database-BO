-- =============================================
-- Migration 014: Agrega campos de horneado al encabezado de proceso
-- Requerimiento: Registrar temperatura de preheat, hora de entrada y salida del horno por producto
-- Script idempotente: seguro de re-ejecutar
-- =============================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND name = 'prh_temperatura_preheat'
)
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
        ADD prh_temperatura_preheat DECIMAL(5, 1) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND name = 'prh_fecha_inicio_horneado'
)
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
        ADD prh_fecha_inicio_horneado DATETIME NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND name = 'prh_fecha_fin_horneado'
)
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
        ADD prh_fecha_fin_horneado DATETIME NULL;
GO
