-- =============================================
-- Migration: 001_CR20260417_AlterTablesVendedoras
-- CR: CR-20260417-01 Formularios Digitales para Vendedoras
-- Fecha: 2026-04-20
-- Descripción: Agrega campos necesarios para los 3 formularios
--              de vendedora: Recepción de Horneado, Control de
--              Repostería y Devolución.
-- =============================================

-- =============================================
-- 1. plh_cat_catalogo_productos
--    + cat_aplica_control_reposteria
--    Indica si el producto aplica al formulario de Control de
--    Repostería (productos con vida útil de 24h).
-- =============================================
ALTER TABLE plh_cat_catalogo_productos
    ADD cat_aplica_control_reposteria BIT NOT NULL DEFAULT 0;
GO

-- =============================================
-- 2. plh_prc_procesos
--    + prc_estado_rotacion
--    + prc_fecha_cierre_rotacion
--    + prc_usuario_cierre_rotacion
--    Trackea el estado del formulario de Control de Repostería
--    (botón Cerrar/Finalizar) a nivel de día/tienda.
--    Estados: PENDIENTE → EN_PROGRESO → FINALIZADO
-- =============================================
ALTER TABLE plh_prc_procesos
    ADD prc_estado_rotacion         NVARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE',
        prc_fecha_cierre_rotacion   DATETIME      NULL,
        prc_usuario_cierre_rotacion NVARCHAR(50)  NULL;
GO

-- =============================================
-- 3. plh_prh_proceso_horneado_encabezado
--    + prh_revisado
--    + prh_fecha_revision
--    + prh_usuario_revision_codigo
--    La vendedora marca cada línea como revisada (autosave).
--    Cuando todas las líneas de una horneada están revisadas
--    y se presiona "Finalizar batch", el batch queda cerrado.
-- =============================================
ALTER TABLE plh_prh_proceso_horneado_encabezado
    ADD prh_revisado               BIT           NOT NULL DEFAULT 0,
        prh_fecha_revision         DATETIME      NULL,
        prh_usuario_revision_codigo NVARCHAR(50) NULL;
GO

-- =============================================
-- 4. plh_prh_proceso_horneado_detalle
--    + prh_motivo_rechazo
--    Obligatorio cuando prh_cantidad_rechazada > 0.
--    Valores permitidos: QUEMADO | TAMAÑO_INCORRECTO | CRUDO
-- =============================================
ALTER TABLE plh_prh_proceso_horneado_detalle
    ADD prh_motivo_rechazo NVARCHAR(50) NULL;
GO

-- =============================================
-- 5. plh_dev_devoluciones
--    + dev_estado
--    + dev_usuario_autorizacion
--    + dev_fecha_autorizacion
--    Flujo de autorización del gerente.
--    Estados: PENDIENTE → AUTORIZADO
-- =============================================
ALTER TABLE plh_dev_devoluciones
    ADD dev_estado               NVARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
        dev_usuario_autorizacion NVARCHAR(50) NULL,
        dev_fecha_autorizacion   DATETIME     NULL;
GO

-- =============================================
-- NOTA: Venta diaria (Aloha)
-- La columna pld_venta_hoy en plh_pld_plan_detalle
-- es el campo destinado a recibir la venta del día
-- desde Aloha. Actualmente se actualiza manualmente.
-- Pendiente: definir integración con la BD de Aloha
-- en Azure para actualización automática.
-- Fórmula saldo disponible para Devolución:
--   saldo = Σ(prh_cantidad_final) - pld_venta_hoy
--           - Σ(rot_cantidad_final) - Σ(dev_cantidad registrada)
-- =============================================
