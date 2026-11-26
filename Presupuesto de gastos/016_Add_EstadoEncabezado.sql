-- =============================================
-- Script: 016_Add_EstadoEncabezado
-- Modulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripcion: Agrega pyl.prg_pen_plan_encabezado.pen_id_estado. Todos los planes
--              existentes quedan en 1 (activo) por el DEFAULT. Solo la columna en
--              base de datos: el backend todavia no la mapea, asi que no cambia
--              ninguna consulta ni ningun INSERT actual.
--              Idempotente: solo agrega la columna si no existe.
-- Base: sm_backoffice
-- Fecha: 2026-10-06
-- =============================================

USE [sm_backoffice];
GO

IF COL_LENGTH('pyl.prg_pen_plan_encabezado', 'pen_id_estado') IS NULL
BEGIN
    ALTER TABLE [pyl].[prg_pen_plan_encabezado]
        ADD pen_id_estado TINYINT NOT NULL CONSTRAINT DF_prg_pen_id_estado DEFAULT (1);
END
GO
