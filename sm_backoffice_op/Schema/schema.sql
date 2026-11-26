-- =============================================
-- Schema Producción: Módulo Plan de Hornos (plh)
-- Base de datos: sm_backoffice_op
-- Estado final: incorpora todas las migraciones 000–021
-- Ejecutar en orden en una DB limpia.
-- =============================================

USE [sm_backoffice_op];
GO

-- ─── 0. Schema ────────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'plh')
    EXEC('CREATE SCHEMA plh');
GO

-- ─── 1. plh_hor_horneadas ────────────────────────────────────────────────────
-- Horneadas configuradas por tienda. Cada horneada define un turno (inicio/fin).

CREATE TABLE [plh].[plh_hor_horneadas] (
    hor_codigo_neg                  NVARCHAR(10)    NOT NULL,
    hor_tienda_codigo               INT             NOT NULL,
    hor_numero_secuencia            INT             NOT NULL,
    hor_hora_inicio                 TIME(0)         NOT NULL,
    hor_hora_fin                    TIME(0)         NOT NULL,
    hor_aplica_pedido_cocina        BIT             NOT NULL CONSTRAINT DF_hor_aplica_pedido_cocina DEFAULT (1),
    hor_activa                      BIT             NOT NULL CONSTRAINT DF_hor_activa DEFAULT (1),
    hor_solo_productos_directos     BIT             NOT NULL CONSTRAINT DF_hor_solo_productos_directos DEFAULT (0),
    hor_fecha_creacion              DATETIME        NOT NULL,
    hor_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL,
    hor_fecha_modificacion          DATETIME        NULL,
    hor_usuario_modificacion_codigo NVARCHAR(20)    NULL,

    CONSTRAINT PK_hor PRIMARY KEY (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
GO

-- ─── 2. plh_log_parametrizacion ──────────────────────────────────────────────
-- Auditoría de cambios en horneadas.

CREATE TABLE [plh].[plh_log_parametrizacion] (
    log_codigo_neg              NVARCHAR(10)    NOT NULL,
    log_tienda_codigo           INT             NOT NULL,
    log_hor_numero_secuencia    INT             NOT NULL,
    log_fecha_hora              DATETIME        NOT NULL,
    log_campo_modificado        NVARCHAR(100)   NOT NULL,
    log_usuario_codigo          NVARCHAR(20)    NOT NULL,
    log_valor_anterior          NVARCHAR(200)   NULL,
    log_valor_nuevo             NVARCHAR(200)   NULL,

    CONSTRAINT PK_log PRIMARY KEY (log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia, log_fecha_hora, log_campo_modificado),
    CONSTRAINT FK_log_hor FOREIGN KEY (log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
GO

-- ─── 3. plh_cat_catalogo_productos ───────────────────────────────────────────
-- Catálogo de productos por tienda/negocio habilitados para el módulo de hornos.

CREATE TABLE [plh].[plh_cat_catalogo_productos] (
    cat_codigo_neg                      NVARCHAR(10)    NOT NULL,
    cat_tienda_codigo                   INT             NOT NULL,
    cat_pro_codigo                      NVARCHAR(50)    NOT NULL,
    cat_pro_nombre                      NVARCHAR(255)   NOT NULL CONSTRAINT DF_cat_pro_nombre DEFAULT (''),
    cat_tipo                            NVARCHAR(20)    NOT NULL CONSTRAINT DF_cat_tipo DEFAULT ('regular'),
    cat_factor_conversion               DECIMAL(10,4)   NOT NULL CONSTRAINT DF_cat_factor DEFAULT (1),
    cat_activo                          BIT             NOT NULL CONSTRAINT DF_cat_activo DEFAULT (1),
    cat_aplica_control_reposteria       BIT             NOT NULL CONSTRAINT DF_cat_aplica_reposteria DEFAULT (0),
    cat_aplica_pedido_cocina            BIT             NOT NULL CONSTRAINT DF_cat_aplica_pedido_cocina DEFAULT (0),
    cat_estacional                      BIT             NOT NULL CONSTRAINT DF_cat_estacional DEFAULT (0),
    cat_pro_terminado_codigo            NVARCHAR(50)    NULL,
    cat_pro_terminado_nombre            NVARCHAR(255)   NULL,
    cat_requiere_fermentacion           BIT             NOT NULL CONSTRAINT DF_cat_requiere_fermentacion DEFAULT (1),
    cat_fraccion_bolsa                  DECIMAL(4,2)    NOT NULL CONSTRAINT DF_cat_fraccion_bolsa DEFAULT (1.00),
    cat_pro_sustituto_codigo            NVARCHAR(50)    NULL,
    cat_fecha_creacion                  DATETIME        NOT NULL,
    cat_usuario_creacion_codigo         NVARCHAR(20)    NOT NULL,
    cat_fecha_modificacion              DATETIME        NULL,
    cat_usuario_modificacion_codigo     NVARCHAR(20)    NULL,

    CONSTRAINT PK_cat PRIMARY KEY (cat_codigo_neg, cat_tienda_codigo, cat_pro_codigo)
);
GO

-- ─── 4. plh_neg_negocios ─────────────────────────────────────────────────────
-- Reemplazada por la vista [plh].[Vw_plh_neg_Negocios].
-- Ver: Views/Vw_plh_neg_Negocios.sql
-- La vista lee directamente desde [sm_backoffice].[pri].[est_neg_negocio].
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 5. plh_mrf_mes_referencia ───────────────────────────────────────────────
-- Mes de referencia por negocio (usado en versiones anteriores del Motor).

CREATE TABLE [plh].[plh_mrf_mes_referencia] (
    mrf_codigo_neg              NVARCHAR(10)    NOT NULL,
    mrf_anio                    INT             NOT NULL,
    mrf_mes                     INT             NOT NULL,
    mrf_fecha_creacion          DATETIME        NOT NULL,
    mrf_usuario_creacion_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_mrf PRIMARY KEY (mrf_codigo_neg, mrf_anio, mrf_mes)
);
GO

-- ─── 6. plh_fct_factor_sku ───────────────────────────────────────────────────
-- Factor mensual por tienda-SKU. Calculado por plh_mrf_CalcularMotorMes.
-- Inmutable: no se puede recalcular un mes ya procesado.

CREATE TABLE [plh].[plh_fct_factor_sku] (
    fct_codigo_neg          NVARCHAR(10)    NOT NULL,
    fct_tienda_codigo       INT             NOT NULL,
    fct_pro_codigo          NVARCHAR(50)    NOT NULL,
    fct_anio_proyectado     INT             NOT NULL,
    fct_mes_proyectado      INT             NOT NULL,
    fct_anio_referencia     INT             NOT NULL,
    fct_mes_referencia      INT             NOT NULL,
    fct_factor_sku          DECIMAL(18,6)   NOT NULL,
    fct_fecha_calculo       DATETIME        NOT NULL CONSTRAINT DF_fct_fecha_calculo DEFAULT GETDATE(),
    fct_usuario_calculo     NVARCHAR(50)    NOT NULL,

    CONSTRAINT PK_plh_fct_factor_sku PRIMARY KEY (fct_codigo_neg, fct_tienda_codigo, fct_pro_codigo, fct_anio_proyectado, fct_mes_proyectado)
);
GO

-- ─── 7. plh_pha_patron_horario ───────────────────────────────────────────────
-- Patrón horario promedio por tienda-día-hora. Calculado por plh_mrf_CalcularMotorMes.

CREATE TABLE [plh].[plh_pha_patron_horario] (
    pha_codigo_neg          NVARCHAR(10)    NOT NULL,
    pha_tienda_codigo       INT             NOT NULL,
    pha_anio_proyectado     INT             NOT NULL,
    pha_mes_proyectado      INT             NOT NULL,
    pha_dia_semana          TINYINT         NOT NULL,   -- 1=Lunes … 7=Domingo
    pha_hora                TINYINT         NOT NULL,   -- 0-23
    pha_porcentaje          DECIMAL(8,6)    NOT NULL,   -- 0.000000 a 1.000000
    pha_fecha_calculo       DATETIME        NOT NULL CONSTRAINT DF_pha_fecha_calculo DEFAULT GETDATE(),
    pha_usuario_calculo     NVARCHAR(50)    NOT NULL,

    CONSTRAINT PK_plh_pha_patron_horario PRIMARY KEY (pha_codigo_neg, pha_tienda_codigo, pha_anio_proyectado, pha_mes_proyectado, pha_dia_semana, pha_hora)
);
GO

-- ─── 8. plh_pla_planes ───────────────────────────────────────────────────────
-- Encabezado del plan diario por tienda.
-- Estados pla_estado: 0=BORRADOR, 1=ACTIVO, 2=CERRADO

CREATE TABLE [plh].[plh_pla_planes] (
    pla_codigo_neg                  NVARCHAR(10)    NOT NULL,
    pla_tienda_codigo               INT             NOT NULL,
    pla_fecha                       DATE            NOT NULL,
    pla_fecha_comparacion           DATE            NULL,
    pla_estado                      TINYINT         NOT NULL CONSTRAINT DF_pla_estado DEFAULT (0),
    pla_fecha_generacion            DATETIME        NOT NULL,
    pla_usuario_generacion_codigo   NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_pla PRIMARY KEY (pla_codigo_neg, pla_tienda_codigo, pla_fecha)
);
GO

-- ─── 9. plh_pld_plan_detalle ─────────────────────────────────────────────────
-- Detalle del plan por producto. Una fila por producto del catálogo activo.

CREATE TABLE [plh].[plh_pld_plan_detalle] (
    pld_codigo_neg          NVARCHAR(10)    NOT NULL,
    pld_tienda_codigo       INT             NOT NULL,
    pld_fecha               DATE            NOT NULL,
    pld_pro_codigo          NVARCHAR(50)    NOT NULL,
    pld_inventario_inicial  DECIMAL(10,2)   NULL,
    pld_proyectado_vender   DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_proyectado DEFAULT (0),
    pld_venta_hoy           DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_venta_hoy DEFAULT (0),
    pld_total_hornear       DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_total_hornear DEFAULT (0),

    CONSTRAINT PK_pld PRIMARY KEY (pld_codigo_neg, pld_tienda_codigo, pld_fecha, pld_pro_codigo),
    CONSTRAINT FK_pld_pla FOREIGN KEY (pld_codigo_neg, pld_tienda_codigo, pld_fecha)
        REFERENCES [plh].[plh_pla_planes] (pla_codigo_neg, pla_tienda_codigo, pla_fecha)
);
GO

-- ─── 10. plh_plh_plan_horneada ───────────────────────────────────────────────
-- Distribución del plan por horneada. Una fila por producto × horneada.

CREATE TABLE [plh].[plh_plh_plan_horneada] (
    plh_codigo_neg                      NVARCHAR(10)    NOT NULL,
    plh_tienda_codigo                   INT             NOT NULL,
    plh_fecha                           DATE            NOT NULL,
    plh_pro_codigo                      NVARCHAR(50)    NOT NULL,
    plh_hor_numero_secuencia            INT             NOT NULL,
    plh_proyeccion                      DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_proyeccion DEFAULT (0),
    plh_pedido_chef                     DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_pedido_chef DEFAULT (0),
    plh_cantidad_hornear                DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_cantidad_hornear DEFAULT (0),
    plh_fecha_actualizacion             DATETIME        NOT NULL,
    plh_usuario_actualizacion_codigo    NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_plh PRIMARY KEY (plh_codigo_neg, plh_tienda_codigo, plh_fecha, plh_pro_codigo, plh_hor_numero_secuencia),
    CONSTRAINT FK_plh_pld FOREIGN KEY (plh_codigo_neg, plh_tienda_codigo, plh_fecha, plh_pro_codigo)
        REFERENCES [plh].[plh_pld_plan_detalle] (pld_codigo_neg, pld_tienda_codigo, pld_fecha, pld_pro_codigo),
    CONSTRAINT FK_plh_hor FOREIGN KEY (plh_codigo_neg, plh_tienda_codigo, plh_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
GO

-- ─── 11. plh_ped_pedidos_cocina ───────────────────────────────────────────────
-- Pedidos a cocina (pre-horneado) por producto × horneada × fecha.
-- Estados ped_estado: 0=PENDIENTE, 1=ENVIADO, 2=COMPLETADO, 3=CANCELADO

CREATE TABLE [plh].[plh_ped_pedidos_cocina] (
    ped_codigo_neg              NVARCHAR(10)    NOT NULL,
    ped_tienda_codigo           INT             NOT NULL,
    ped_fecha                   DATE            NOT NULL,
    ped_pro_codigo              NVARCHAR(50)    NOT NULL,
    ped_hor_numero_secuencia    INT             NOT NULL,
    ped_cantidad                DECIMAL(10,2)   NOT NULL CONSTRAINT DF_ped_cantidad DEFAULT (0),
    ped_estado                  TINYINT         NOT NULL CONSTRAINT DF_ped_estado DEFAULT (0),
    ped_fecha_creacion          DATETIME        NOT NULL,
    ped_usuario_creacion_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_ped PRIMARY KEY (ped_codigo_neg, ped_tienda_codigo, ped_fecha, ped_pro_codigo, ped_hor_numero_secuencia),
    CONSTRAINT FK_ped_hor FOREIGN KEY (ped_codigo_neg, ped_tienda_codigo, ped_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
GO

-- ─── 12. plh_prc_procesos ─────────────────────────────────────────────────────
-- Proceso diario de horneado por tienda.
-- Estados prc_estado:         0=PENDIENTE, 1=EN_PROCESO, 2=FINALIZADO
-- Estados prc_estado_rotacion: 0=PENDIENTE, 1=FINAL_CERRADO, 2=CERRADO

CREATE TABLE [plh].[plh_prc_procesos] (
    prc_codigo_neg              NVARCHAR(10)    NOT NULL,
    prc_tienda_codigo           INT             NOT NULL,
    prc_fecha                   DATE            NOT NULL,
    prc_estado                  TINYINT         NOT NULL CONSTRAINT DF_prc_estado DEFAULT (0),
    prc_fecha_inicio            DATETIME        NULL,
    prc_fecha_fin               DATETIME        NULL,
    prc_usuario_inicio_codigo   NVARCHAR(20)    NULL,
    prc_usuario_fin_codigo      NVARCHAR(20)    NULL,
    prc_estado_rotacion         TINYINT         NOT NULL CONSTRAINT DF_prc_estado_rotacion DEFAULT (0),
    prc_fecha_cierre_final      DATETIME        NULL,
    prc_usuario_cierre_final    NVARCHAR(50)    NULL,
    prc_fecha_cierre_rotacion   DATETIME        NULL,
    prc_usuario_cierre_rotacion NVARCHAR(50)    NULL,

    CONSTRAINT PK_prc PRIMARY KEY (prc_codigo_neg, prc_tienda_codigo, prc_fecha)
);
GO

-- ─── 13. plh_prh_proceso_horneado_encabezado ──────────────────────────────────
-- Encabezado por producto × horneada dentro del proceso diario.
-- Estados prh_estado_fermentacion: 0=PENDIENTE, 1=EN_FERMENTACION, 2=FERMENTADO, 3=COMPLETADO

CREATE TABLE [plh].[plh_prh_proceso_horneado_encabezado] (
    prh_codigo_neg                      NVARCHAR(10)    NOT NULL,
    prh_tienda_codigo                   INT             NOT NULL,
    prh_fecha                           DATE            NOT NULL,
    prh_pro_codigo                      NVARCHAR(50)    NOT NULL,
    prh_hor_numero_secuencia            INT             NOT NULL,
    prh_cantidad_bolsas                 DECIMAL(10,2)   NOT NULL CONSTRAINT DF_prh_cantidad_bolsas DEFAULT (0),
    prh_estado_fermentacion             TINYINT         NOT NULL CONSTRAINT DF_prh_estado_fermentacion DEFAULT (0),
    prh_fecha_inicio_ferment            DATETIME        NULL,
    prh_fecha_fin_ferment               DATETIME        NULL,
    prh_rack_asignado                   NVARCHAR(20)    NULL,
    prh_temperatura_preheat             DECIMAL(5,1)    NULL,
    prh_temperatura_preheat_2           DECIMAL(5,1)    NULL,
    prh_temperatura_horno               DECIMAL(5,1)    NULL,
    prh_temperatura_horno_2             DECIMAL(5,1)    NULL,
    prh_vapor_segundos                  INT             NULL,
    prh_omitio_fermentacion             BIT             NOT NULL CONSTRAINT DF_prh_omitio DEFAULT (0),
    prh_temperatura_descongelamiento    DECIMAL(5,1)    NULL,
    prh_fecha_inicio_horneado           DATETIME        NULL,
    prh_fecha_fin_horneado              DATETIME        NULL,
    prh_observaciones                   NVARCHAR(500)   NULL,
    prh_revisado                        BIT             NOT NULL CONSTRAINT DF_prh_revisado DEFAULT (0),
    prh_fecha_revision                  DATETIME        NULL,
    prh_usuario_revision_codigo         NVARCHAR(50)    NULL,
    prh_fecha_actualizacion             DATETIME        NOT NULL,
    prh_usuario_actualizacion_codigo    NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_prh_enc PRIMARY KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia),
    CONSTRAINT FK_prh_prc FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha)
        REFERENCES [plh].[plh_prc_procesos] (prc_codigo_neg, prc_tienda_codigo, prc_fecha),
    CONSTRAINT FK_prh_hor FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
GO

-- ─── 14. plh_prh_proceso_horneado_detalle ────────────────────────────────────
-- Resultado de recepción (aceptado / rechazado / final) por encabezado.

CREATE TABLE [plh].[plh_prh_proceso_horneado_detalle] (
    prh_codigo_neg              NVARCHAR(10)    NOT NULL,
    prh_tienda_codigo           INT             NOT NULL,
    prh_fecha                   DATE            NOT NULL,
    prh_pro_codigo              NVARCHAR(50)    NOT NULL,
    prh_hor_numero_secuencia    INT             NOT NULL,
    prh_cantidad_aceptada       DECIMAL(10,2)   NULL,
    prh_cantidad_rechazada      DECIMAL(10,2)   NULL,
    prh_motivo_rechazo          NVARCHAR(50)    NULL,
    prh_cantidad_final          DECIMAL(10,2)   NULL,
    prh_fecha_registro          DATETIME        NOT NULL,
    prh_usuario_registro_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_prh_det PRIMARY KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia),
    CONSTRAINT FK_prh_det_enc FOREIGN KEY (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_prh_proceso_horneado_encabezado] (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia)
);
GO

-- ─── 15. plh_tip_tipos_evento ────────────────────────────────────────────────
-- Catálogo de tipos de evento de trazabilidad.

CREATE TABLE [plh].[plh_tip_tipos_evento] (
    tip_id          TINYINT         NOT NULL,
    tip_descripcion NVARCHAR(100)   NOT NULL,
    CONSTRAINT PK_tip PRIMARY KEY (tip_id)
);
INSERT INTO [plh].[plh_tip_tipos_evento] (tip_id, tip_descripcion) VALUES
    (1, 'Inicio de fermentación'),
    (2, 'Fin de fermentación'),
    (3, 'Entró al horno'),
    (4, 'Salió del horno'),
    (5, 'Resultado registrado'),
    (6, 'Temperatura registrada'),
    (7, 'Observación'),
    (8, 'Agregado (legacy)');
GO

GRANT SELECT ON [plh].[plh_tip_tipos_evento] TO [Plh_app_user];
GO

-- ─── 16. plh_trz_trazabilidad ────────────────────────────────────────────────
-- Bitácora de eventos por encabezado. trz_tip_id referencia plh_tip_tipos_evento.

CREATE TABLE [plh].[plh_trz_trazabilidad] (
    trz_id                          BIGINT          NOT NULL IDENTITY(1,1),
    trz_prh_codigo_neg              NVARCHAR(10)    NOT NULL,
    trz_prh_tienda_codigo           INT             NOT NULL,
    trz_prh_fecha                   DATE            NOT NULL,
    trz_prh_pro_codigo              NVARCHAR(50)    NOT NULL,
    trz_prh_hor_numero_secuencia    INT             NOT NULL,
    trz_tip_id                      TINYINT         NOT NULL,
    trz_fecha_evento                DATETIME        NOT NULL,
    trz_usuario_codigo              NVARCHAR(20)    NOT NULL,
    trz_observaciones               NVARCHAR(500)   NULL,

    CONSTRAINT PK_trz PRIMARY KEY (trz_id),
    CONSTRAINT FK_trz_prh FOREIGN KEY (trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha, trz_prh_pro_codigo, trz_prh_hor_numero_secuencia)
        REFERENCES [plh].[plh_prh_proceso_horneado_encabezado] (prh_codigo_neg, prh_tienda_codigo, prh_fecha, prh_pro_codigo, prh_hor_numero_secuencia),
    CONSTRAINT FK_trz_tip FOREIGN KEY (trz_tip_id)
        REFERENCES [plh].[plh_tip_tipos_evento] (tip_id)
);
CREATE NONCLUSTERED INDEX IX_trz_prh_fk
    ON [plh].[plh_trz_trazabilidad] (trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha, trz_prh_pro_codigo, trz_prh_hor_numero_secuencia)
    INCLUDE (trz_tip_id, trz_fecha_evento, trz_usuario_codigo, trz_observaciones);
GO

-- ─── 16. plh_rot_rotacion ────────────────────────────────────────────────────
-- Cantidad final en display por producto × horneada (Control de Repostería).
-- rot_hor_id = NULL cuando es transferencia (rot_es_transferencia = 1).

CREATE TABLE [plh].[plh_rot_rotacion] (
    rot_codigo_neg              NVARCHAR(10)    NOT NULL,
    rot_tienda_codigo           INT             NOT NULL,
    rot_id                      BIGINT          NOT NULL IDENTITY(1,1),
    rot_fecha                   DATE            NOT NULL,
    rot_pro_codigo              NVARCHAR(50)    NOT NULL,
    rot_hor_numero_secuencia    INT             NULL,
    rot_es_transferencia        BIT             NOT NULL CONSTRAINT DF_rot_es_transferencia DEFAULT (0),
    rot_cantidad_final          DECIMAL(10,2)   NOT NULL CONSTRAINT DF_rot_cantidad DEFAULT (0),
    rot_fecha_registro          DATETIME        NOT NULL,
    rot_usuario_registro_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_rot PRIMARY KEY (rot_id),
    CONSTRAINT FK_rot_hor FOREIGN KEY (rot_codigo_neg, rot_tienda_codigo, rot_hor_numero_secuencia)
        REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
);
CREATE UNIQUE INDEX UQ_rot_fecha_tienda_producto_horneada
    ON [plh].[plh_rot_rotacion] (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_pro_codigo, rot_hor_numero_secuencia)
    WHERE rot_hor_numero_secuencia IS NOT NULL;
CREATE INDEX IX_rot_transferencias
    ON [plh].[plh_rot_rotacion] (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_es_transferencia)
    WHERE rot_es_transferencia = 1;
GO

-- ─── 17. plh_dev_devoluciones ────────────────────────────────────────────────
-- Devoluciones de producto por tienda/fecha. Múltiples registros por producto/día.
-- Estados dev_estado: 0=PENDIENTE, 1=AUTORIZADO

CREATE TABLE [plh].[plh_dev_devoluciones] (
    dev_codigo_neg                  NVARCHAR(10)    NOT NULL,
    dev_tienda_codigo               INT             NOT NULL,
    dev_id                          BIGINT          NOT NULL IDENTITY(1,1),
    dev_fecha_registro              DATE            NOT NULL,
    dev_fecha_venta                 DATE            NOT NULL,
    dev_pro_codigo                  NVARCHAR(50)    NOT NULL,
    dev_hor_id                      BIGINT          NULL,
    dev_hor_numero_secuencia        INT             NULL,
    dev_cantidad                    DECIMAL(10,2)   NOT NULL CONSTRAINT DF_dev_cantidad DEFAULT (0),
    dev_observaciones               NVARCHAR(500)   NULL,
    dev_estado                      TINYINT         NOT NULL CONSTRAINT DF_dev_estado DEFAULT (0),
    dev_usuario_autorizacion        NVARCHAR(50)    NULL,
    dev_fecha_autorizacion          DATETIME        NULL,
    dev_dia_cerrado                 BIT             NOT NULL CONSTRAINT DF_dev_dia_cerrado DEFAULT (0),
    dev_origen_cocina               BIT             NOT NULL CONSTRAINT DF_dev_origen_cocina DEFAULT (0),
    dev_fecha_creacion              DATETIME        NOT NULL,
    dev_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_dev PRIMARY KEY (dev_id)
    -- Sin UNIQUE por producto/día: se permiten múltiples registros intra-día.
);
CREATE NONCLUSTERED INDEX IX_dev_codigoNeg_tienda_fecha
    ON [plh].[plh_dev_devoluciones] (dev_codigo_neg, dev_tienda_codigo, dev_fecha_registro)
    INCLUDE (dev_fecha_venta, dev_pro_codigo, dev_cantidad, dev_observaciones,
             dev_dia_cerrado, dev_fecha_creacion, dev_usuario_creacion_codigo,
             dev_hor_numero_secuencia, dev_origen_cocina);
GO

-- ─── 18. plh_rec_recepciones_chef ───────────────────────────────────────────
-- Ledger de recepciones del chef (CR-20260816-01 Devolución Cocina).
-- Un registro por cada vez que el chef confirma haber recibido producto,
-- a lo largo del día. Sin UNIQUE por producto/día: se permiten múltiples
-- registros intra-día (acumulable) — el total se obtiene con SUM.

CREATE TABLE [plh].[plh_rec_recepciones_chef] (
    rec_codigo_neg               NVARCHAR(10)    NOT NULL,
    rec_tienda_codigo            INT             NOT NULL,
    rec_id                       BIGINT          NOT NULL IDENTITY(1,1),
    rec_fecha                    DATE            NOT NULL,
    rec_pro_codigo                NVARCHAR(50)    NOT NULL,
    rec_cantidad                 DECIMAL(10,2)   NOT NULL CONSTRAINT DF_rec_cantidad DEFAULT (0),
    rec_fecha_registro           DATETIME        NOT NULL CONSTRAINT DF_rec_fecha_registro DEFAULT (GETDATE()),
    rec_usuario_registro_codigo  NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_rec PRIMARY KEY (rec_id)
);
CREATE INDEX IX_rec_fecha_tienda_producto
    ON [plh].[plh_rec_recepciones_chef] (rec_codigo_neg, rec_tienda_codigo, rec_fecha, rec_pro_codigo);
GO

-- ─── 19. Permisos ─────────────────────────────────────────────────────────────

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::plh TO [Plh_app_user];
GO
