-- CR-20260914-01 — Horneada Extraordinaria: reusa las tablas ya existentes en vez de
-- crear tablas nuevas (plh_hor_horneadas para "configurarla" con secuencia 999 +
-- bandera, y plh_prh_proceso_horneado_encabezado para el motivo/número de check).
--
-- plh_hor_horneadas.hor_es_extraordinaria: marca la fila "placeholder" (secuencia 999,
-- por tienda) que se crea la primera vez que un Gerente registra una Horneada
-- Extraordinaria en esa tienda. Se deja hor_activa = 1 a propósito para que aparezca
-- como una pestaña normal en Proceso de Hornos (el chef la ve igual que cualquier
-- horneada) — plh_pla_GenerarPlan la excluye explícitamente para que NO aparezca como
-- columna en el Plan de Hornos (ver 03_Plan.sql).
--
-- plh_prh_proceso_horneado_encabezado.prh_numero_check: número de transacción de Aloha
-- que respalda la venta (campo obligatorio del CR). El motivo se guarda en la columna
-- ya existente prh_observaciones.

USE [sm_backoffice_op];
GO

ALTER TABLE [plh].[plh_hor_horneadas]
ADD hor_es_extraordinaria BIT NOT NULL
    CONSTRAINT DF_hor_es_extraordinaria DEFAULT (0);
GO

ALTER TABLE [plh].[plh_prh_proceso_horneado_encabezado]
ADD prh_numero_check NVARCHAR(50) NULL;
GO
