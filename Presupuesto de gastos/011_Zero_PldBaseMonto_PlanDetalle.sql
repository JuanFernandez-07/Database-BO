-- =============================================
-- Script: 011_Zero_PldBaseMonto_PlanDetalle
-- Modulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripcion: Pone en 0 pyl.prg_pld_plan_detalle.pld_base_monto para todas
--              las filas existentes. Ya no se usa: era un snapshot del monto
--              de Venta guardado como "base" del % en cada fila de cada rubro,
--              pero desde que la Venta vive en su propia fila (id_rubro tipo
--              Venta, ver ActualizarLineaPlanCommandHandler.cs) duplicarla en
--              todas las demas filas quedo redundante. El codigo (PlanDetalle.cs
--              - ActualizarMonto/ActualizarPct/ActualizarDesdeMenu) ya dejo de
--              escribir este campo (decision del usuario 2026-09-28) - este
--              script solo limpia las filas que ya se habian guardado con el
--              codigo viejo. No afecta pld_monto ni pld_pct (el calculo del %
--              no cambio, solo se dejo de duplicar el monto de venta como base).
--              Idempotente: seguro de re-ejecutar (solo toca filas que aun no
--              esten en 0).
-- Base: sm_backoffice
-- Fecha: 2026-09-28
-- =============================================

USE [sm_backoffice];
GO

UPDATE [pyl].[prg_pld_plan_detalle]
SET pld_base_monto = 0
WHERE pld_base_monto <> 0;
GO