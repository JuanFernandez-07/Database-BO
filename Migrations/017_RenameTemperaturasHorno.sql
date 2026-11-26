-- ============================================================
-- Migración 017 — Renombrar columnas de temperatura en encabezado
-- Clarifica semántica: 2 precalentamiento + 2 horneado.
-- Ejecutar en sm_backoffice_op (entorno de desarrollo/test)
-- ============================================================

-- Renombrar prh_temperatura_2  → prh_temperatura_preheat_2  (Precalentamiento 2)
EXEC sp_rename
    'plh.plh_prh_proceso_horneado_encabezado.prh_temperatura_2',
    'prh_temperatura_preheat_2',
    'COLUMN';
GO

-- Renombrar prh_temperatura_3 → prh_temperatura_horno_2  (Horneado 2)
EXEC sp_rename
    'plh.plh_prh_proceso_horneado_encabezado.prh_temperatura_3',
    'prh_temperatura_horno_2',
    'COLUMN';
GO

-- Eliminar prh_temperatura_4 (no requerida — solo hay 2 pre + 2 horno)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_encabezado')
      AND name = 'prh_temperatura_4'
)
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
        DROP COLUMN prh_temperatura_4;
GO
