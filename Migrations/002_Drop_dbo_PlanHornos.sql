-- =============================================
-- Migración: 002_Drop_dbo_PlanHornos
-- Descripción: Elimina todos los objetos del módulo Plan de Hornos
--              que están actualmente en el schema dbo.
--              Ejecutar ANTES de 003_Create_plh_Schema_Tables.sql
-- Fecha: 2026-04-23
-- =============================================

-- ─── 1. Stored Procedures ────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS [dbo].[plh_rep_ReporteDevolucionesPeriodo];
DROP PROCEDURE IF EXISTS [dbo].[plh_rep_ReporteHornos];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_rot_GetRotacion];
DROP PROCEDURE IF EXISTS [dbo].[plh_rot_RegistrarRotacion];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_dev_GetDevoluciones];
DROP PROCEDURE IF EXISTS [dbo].[plh_dev_RegistrarDevolucion];
DROP PROCEDURE IF EXISTS [dbo].[plh_dev_EliminarDevolucion];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_prh_GetRecepcionHorneado];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_AgregarEncabezado];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_EliminarEncabezado];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_IniciarFermentacion];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_FinalizarFermentacion];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_RegistrarResultado];
DROP PROCEDURE IF EXISTS [dbo].[plh_prh_MarcarRevisado];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_prc_IniciarProceso];
DROP PROCEDURE IF EXISTS [dbo].[plh_prc_FinalizarProceso];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_ped_GuardarPedidoCocina];
DROP PROCEDURE IF EXISTS [dbo].[plh_ped_ActualizarEstadoPedido];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_pla_GenerarPlan];
DROP PROCEDURE IF EXISTS [dbo].[plh_pla_ActualizarDetalle];
DROP PROCEDURE IF EXISTS [dbo].[plh_pla_ActualizarPlanHorneada];
DROP PROCEDURE IF EXISTS [dbo].[plh_pla_ActualizarEstadoPlan];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_mrf_GuardarMesReferencia];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_cat_GuardarProducto];
GO

DROP PROCEDURE IF EXISTS [dbo].[plh_hor_GuardarHorneada];
DROP PROCEDURE IF EXISTS [dbo].[plh_hor_DesactivarHorneada];
GO

-- ─── 2. Vista ─────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS [dbo].[Vw_plh_Productos];
GO

-- ─── 3. Tablas (orden inverso de FK) ─────────────────────────────────────────

-- Hojas sin dependientes
DROP TABLE IF EXISTS [dbo].[plh_dev_devoluciones];
DROP TABLE IF EXISTS [dbo].[plh_rot_rotacion];
GO

-- Detalles y trazabilidad (dependen de encabezado)
DROP TABLE IF EXISTS [dbo].[plh_trz_trazabilidad];
DROP TABLE IF EXISTS [dbo].[plh_prh_proceso_horneado_detalle];
GO

-- Encabezado (depende de procesos y horneadas)
DROP TABLE IF EXISTS [dbo].[plh_prh_proceso_horneado_encabezado];
GO

-- Procesos y pedidos (dependen de horneadas)
DROP TABLE IF EXISTS [dbo].[plh_prc_procesos];
DROP TABLE IF EXISTS [dbo].[plh_ped_pedidos_cocina];
GO

-- Plan horneada (depende de plan detalle y horneadas)
DROP TABLE IF EXISTS [dbo].[plh_plh_plan_horneada];
GO

-- Plan detalle (depende de planes)
DROP TABLE IF EXISTS [dbo].[plh_pld_plan_detalle];
GO

-- Planes y log (dependen de horneadas)
DROP TABLE IF EXISTS [dbo].[plh_pla_planes];
DROP TABLE IF EXISTS [dbo].[plh_log_parametrizacion];
GO

-- Tablas raíz (sin dependencias entre ellas)
DROP TABLE IF EXISTS [dbo].[plh_mrf_mes_referencia];
DROP TABLE IF EXISTS [dbo].[plh_cat_catalogo_productos];
DROP TABLE IF EXISTS [dbo].[plh_hor_horneadas];
GO
