-- =============================================
-- Script: 010_Add_PldOrden_PlanDetalle
-- Modulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripcion: Agrega pyl.prg_pld_plan_detalle.pld_orden y lo llena con el
--              rub_orden ya definido en el catalogo pyl.prg_rub_rubro. Es una
--              excepcion deliberada al comentario de 001_Create_pyl_Schema_Tables.sql
--              ("Solo valores por tienda/mes - la metadata ya vive en
--              prg_rub_rubro y se obtiene por JOIN, no se duplica aqui"): SOLO
--              el orden se denormaliza (no nombre/tipo_dato/aplica_menu), para
--              que consultas SQL directas/reportes puedan ordenar sin JOIN.
--              Mismo patron/tipo de dato que pyl.vta_rme_reporte_mes.rme_orden
--              (INT), que ya denormaliza orden en ese mismo modulo.
--              Confirmado con el usuario 2026-09-28.
--              Idempotente: seguro de re-ejecutar (ALTER solo si falta la
--              columna, UPDATE solo de filas desalineadas).
-- Base: sm_backoffice
-- Fecha: 2026-09-28
-- =============================================

USE [sm_backoffice];
GO

-- 1. Columna
IF COL_LENGTH('pyl.prg_pld_plan_detalle', 'pld_orden') IS NULL
BEGIN
    ALTER TABLE [pyl].[prg_pld_plan_detalle]
        ADD pld_orden INT NOT NULL CONSTRAINT DF_prg_pld_orden DEFAULT (0);
END
GO

-- 2. Backfill de filas existentes (JOIN por negocio/reporte/rubro, mismo
--    criterio que la FK FK_prg_pld_rub ya declarada en 001_Create_pyl_Schema_Tables.sql)
UPDATE d
SET d.pld_orden = r.rub_orden
FROM [pyl].[prg_pld_plan_detalle] AS d
INNER JOIN [pyl].[prg_rub_rubro] AS r
    ON d.pld_id_negocio = r.rub_id_negocio
   AND d.pld_id_reporte = r.rub_id_reporte
   AND d.pld_id_rubro   = r.rub_id_rubro
WHERE d.pld_orden <> r.rub_orden;
GO
