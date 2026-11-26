-- Agrega columna hor_dias_antes_inicio a plh_hor_horneadas.
-- Indica cuántos días antes de la fecha del plan arranca el bloqueo de esa
-- horneada. 0 = mismo día (default, comportamiento actual sin cambios).
-- H1 fermenta desde la tarde/noche del día anterior en todas las tiendas,
-- así que su bloqueo real cae un día antes de la fecha del plan: se
-- configura en 1 (ver seed al final de este script).
-- CR-20260914-01 — Bloqueo de Horneadas y Pedido Extraordinario.

USE [sm_backoffice_op];
GO

ALTER TABLE [plh].[plh_hor_horneadas]
ADD hor_dias_antes_inicio TINYINT NOT NULL
    CONSTRAINT DF_hor_dias_antes_inicio DEFAULT (0);
GO

-- Seed: H1 (numero_secuencia = 1) fermenta desde el día anterior en todas
-- las tiendas activas. Ajustar manualmente si alguna tienda tiene otra
-- convención de numeración para H1.
UPDATE [plh].[plh_hor_horneadas]
SET hor_dias_antes_inicio = 1
WHERE hor_numero_secuencia = 1;
GO
