-- =============================================
-- Fase 2 (HORNOS-F2-DEVO): estado persistido de cierre de DEVO por área.
--
-- Antes "cerrada" se calculaba en vivo desde plh_dev_devoluciones (sin columnas
-- nuevas) — pero eso no puede representar "cerré el día sin ningún registro"
-- (toda la devolución en 0, o simplemente no hubo nada que registrar), que SÍ es
-- un caso válido de negocio: cerrar con cero registros reales debe quedar
-- marcado como cerrado igual, no solo cuando hay al menos una fila.
--
-- La bandera ES el estado — ya no se infiere de si hay filas abiertas o no.
-- =============================================

USE [sm_backoffice_op];
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prc_procesos')
      AND name = 'prc_devo_panaderia_cerrada'
)
BEGIN
    ALTER TABLE plh.plh_prc_procesos
        ADD prc_devo_panaderia_cerrada BIT NOT NULL CONSTRAINT DF_prc_devo_panaderia_cerrada DEFAULT (0);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prc_procesos')
      AND name = 'prc_devo_cocina_cerrada'
)
BEGIN
    ALTER TABLE plh.plh_prc_procesos
        ADD prc_devo_cocina_cerrada BIT NOT NULL CONSTRAINT DF_prc_devo_cocina_cerrada DEFAULT (0);
END
GO
