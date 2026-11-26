-- Migración 013: Eliminar tabla plh_rot_cierres_dia
-- Razón: la columna prc_estado_rotacion en plh_prc_procesos ya cumple esta función.
-- Idempotente: solo dropea si aún existe.

USE [sm_backoffice_op];
GO

IF EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID('plh.plh_rot_cierres_dia')
)
BEGIN
    DROP TABLE plh.plh_rot_cierres_dia;
    PRINT 'Tabla plh_rot_cierres_dia eliminada.';
END
ELSE
    PRINT 'Tabla plh_rot_cierres_dia no existe, nada que hacer.';
GO
