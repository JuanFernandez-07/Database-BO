-- =============================================
-- Migration 010: Agrega campo temperatura_horno al encabezado de proceso
-- Requerimiento: El hornero debe registrar en la bitácora: temperaturas, horas y observaciones
-- =============================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND name = 'prh_temperatura_horno'
)
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
        ADD prh_temperatura_horno DECIMAL(5, 1) NULL;
GO
