-- =============================================
-- Script: 007_Fix_TipoDato_EmpleadosPlanillas_Motivacion
-- Modulo: Presupuesto de Gastos (P&L Tiendas) - correccion de catalogo
-- Descripcion: Reafirma pyl.prg_rub_rubro.rub_tipo_dato de los 16 rubros hoja
--              (Costo de Venta + Gastos Controlables) segun la regla de
--              negocio confirmada por el usuario (2026-09-23, re-confirmada
--              2026-09-25): SOLO Costo de Comida, Empaque, Flete y Gastos
--              Mercadeo son Porcentaje (3) - el resto es Monto (4).
--              Version 2 (09-25): ya no solo corrige Empleados Planillas/
--              Motivacion (8/19) condicionado a que esten mal - reafirma los
--              16 rubros explicitamente sin importar su valor actual, porque
--              el catalogo ya se revirtio una vez a un estado viejo (posible
--              re-siembra de un 002_Seed_Catalogo.sql desactualizado via
--              backup o pipeline) y una condicion "solo si esta en 3" no
--              protege contra otros escenarios de drift.
--              Seguro de re-ejecutar aunque ya existan filas capturadas en
--              pyl.prg_pld_plan_detalle para estos rubros: PlanDetalle.cs
--              (ActualizarPct) siempre guarda Monto y Pct sincronizados sin
--              importar cual de los dos capturo el usuario, asi que
--              pld_monto ya tiene el valor correcto en dinero y no se pierde
--              nada al cambiar que columna lee el resolver.
--              Este mismo cambio ya quedo corregido en 002_Seed_Catalogo.sql
--              para que un ambiente nuevo lo siembre bien desde el inicio.
-- Base: sm_backoffice
-- Fecha: 2026-09-25
-- =============================================

USE [sm_backoffice];
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

UPDATE r
SET r.rub_tipo_dato = origen.tipo_dato
FROM [pyl].[prg_rub_rubro] AS r
INNER JOIN (VALUES
    -- id_rubro, tipo_dato (3 = Porcentaje, 4 = Monto)
    (3,  3),  -- Costo de Comida
    (4,  3),  -- Empaque
    (5,  3),  -- Flete
    (8,  4),  -- Empleados Planillas
    (9,  4),  -- Servicios Publicos
    (10, 4),  -- Mantenimiento
    (11, 4),  -- Suministros y Cristaleria
    (12, 4),  -- Limpieza y Operacion
    (13, 4),  -- Papeleria y Utiles
    (14, 4),  -- Uniformes
    (15, 4),  -- Servicios Externos
    (16, 4),  -- Viajes y Viaticos
    (17, 4),  -- Seguridad Industrial
    (18, 3),  -- Gastos Mercadeo
    (19, 4),  -- Motivacion y Reconocimiento
    (20, 4)   -- Capacitacion
) AS origen (id_rubro, tipo_dato) ON r.rub_id_rubro = origen.id_rubro
WHERE r.rub_id_negocio = @idNegocio AND r.rub_id_reporte = @idReporte
  AND r.rub_tipo_dato <> origen.tipo_dato;
GO
