-- =============================================
-- Schema: Plan de Hornos (plh_*)
-- Descripción: Creación de tablas del módulo Plan de Hornos.
--              Ejecutar en orden. Requiere que exista Vw_plh_Productos.
-- Fecha: 2026-04-22
-- =============================================

-- ─── 1. Horneadas ────────────────────────────────────────────────────────────

CREATE TABLE plh_hor_horneadas (
    hor_id                          BIGINT          NOT NULL IDENTITY(1,1),
    hor_codigo_neg                  NVARCHAR(10)    NOT NULL,
    hor_tienda_codigo               INT             NOT NULL,
    hor_numero_secuencia            INT             NOT NULL,
    hor_hora_inicio                 TIME(0)         NOT NULL,
    hor_hora_fin                    TIME(0)         NOT NULL,
    hor_aplica_pedido_cocina        BIT             NOT NULL CONSTRAINT DF_hor_aplica_pedido_cocina DEFAULT (1),
    hor_activa                      BIT             NOT NULL CONSTRAINT DF_hor_activa DEFAULT (1),
    hor_fecha_creacion              DATETIME        NOT NULL,
    hor_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL,
    hor_fecha_modificacion          DATETIME        NULL,
    hor_usuario_modificacion_codigo NVARCHAR(20)    NULL,

    CONSTRAINT PK_hor PRIMARY KEY (hor_id),
    CONSTRAINT UQ_hor_tienda_secuencia UNIQUE (hor_tienda_codigo, hor_codigo_neg, hor_numero_secuencia)
);
GO

-- ─── 2. Log de parametrización ───────────────────────────────────────────────

CREATE TABLE plh_log_parametrizacion (
    log_id                  BIGINT          NOT NULL IDENTITY(1,1),
    log_hor_id              BIGINT          NOT NULL,
    log_usuario_codigo      NVARCHAR(20)    NOT NULL,
    log_fecha_hora          DATETIME        NOT NULL,
    log_campo_modificado    NVARCHAR(100)   NOT NULL,
    log_valor_anterior      NVARCHAR(200)   NULL,
    log_valor_nuevo         NVARCHAR(200)   NULL,

    CONSTRAINT PK_log PRIMARY KEY (log_id),
    CONSTRAINT FK_log_hor FOREIGN KEY (log_hor_id) REFERENCES plh_hor_horneadas (hor_id)
);
GO

-- ─── 3. Catálogo de productos ─────────────────────────────────────────────────

CREATE TABLE plh_cat_catalogo_productos (
    cat_id                          BIGINT          NOT NULL IDENTITY(1,1),
    cat_codigo_neg                  NVARCHAR(10)    NOT NULL,
    cat_tienda_codigo               INT             NOT NULL,
    cat_pro_codigo                  NVARCHAR(50)    NOT NULL,
    cat_tipo                        NVARCHAR(20)    NOT NULL CONSTRAINT DF_cat_tipo DEFAULT ('regular'),
    cat_factor_conversion           DECIMAL(10,4)   NOT NULL CONSTRAINT DF_cat_factor DEFAULT (1),
    cat_activo                      BIT             NOT NULL CONSTRAINT DF_cat_activo DEFAULT (1),
    cat_fecha_creacion              DATETIME        NOT NULL,
    cat_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL,
    cat_fecha_modificacion          DATETIME        NULL,
    cat_usuario_modificacion_codigo NVARCHAR(20)    NULL,

    CONSTRAINT PK_cat PRIMARY KEY (cat_id),
    CONSTRAINT UQ_cat_tienda_producto UNIQUE (cat_tienda_codigo, cat_codigo_neg, cat_pro_codigo)
);
GO

-- ─── 4. Mes de referencia ─────────────────────────────────────────────────────

CREATE TABLE plh_mrf_mes_referencia (
    mrf_id                      BIGINT          NOT NULL IDENTITY(1,1),
    mrf_codigo_neg              NVARCHAR(10)    NOT NULL,
    mrf_anio                    INT             NOT NULL,
    mrf_mes                     INT             NOT NULL,
    mrf_fecha_creacion          DATETIME        NOT NULL,
    mrf_usuario_creacion_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_mrf PRIMARY KEY (mrf_id),
    CONSTRAINT UQ_mrf_codigo_neg_anio_mes UNIQUE (mrf_codigo_neg, mrf_anio, mrf_mes)
);
GO

-- ─── 5. Planes ────────────────────────────────────────────────────────────────

CREATE TABLE plh_pla_planes (
    pla_id                          BIGINT          NOT NULL IDENTITY(1,1),
    pla_codigo_neg                  NVARCHAR(10)    NOT NULL,
    pla_tienda_codigo               INT             NOT NULL,
    pla_fecha                       DATE            NOT NULL,
    pla_fecha_comparacion           DATE            NOT NULL,
    pla_estado                      NVARCHAR(20)    NOT NULL CONSTRAINT DF_pla_estado DEFAULT ('borrador'),
    pla_fecha_generacion            DATETIME        NOT NULL,
    pla_usuario_generacion_codigo   NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_pla PRIMARY KEY (pla_id),
    CONSTRAINT UQ_pla_fecha_tienda UNIQUE (pla_fecha, pla_tienda_codigo, pla_codigo_neg)
);
GO

-- ─── 6. Plan detalle (productos del plan) ────────────────────────────────────

CREATE TABLE plh_pld_plan_detalle (
    pld_id                  BIGINT          NOT NULL IDENTITY(1,1),
    pld_pla_id              BIGINT          NOT NULL,
    pld_pro_codigo          NVARCHAR(50)    NOT NULL,
    pld_inventario_inicial  DECIMAL(10,2)   NULL,
    pld_proyectado_vender   DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_proyectado DEFAULT (0),
    pld_venta_hoy           DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_venta_hoy DEFAULT (0),
    pld_total_hornear       DECIMAL(10,2)   NOT NULL CONSTRAINT DF_pld_total_hornear DEFAULT (0),

    CONSTRAINT PK_pld PRIMARY KEY (pld_id),
    CONSTRAINT FK_pld_pla FOREIGN KEY (pld_pla_id) REFERENCES plh_pla_planes (pla_id),
    CONSTRAINT UQ_pld_plan_producto UNIQUE (pld_pla_id, pld_pro_codigo)
);
GO

-- ─── 7. Plan horneada (distribución por turno) ───────────────────────────────

CREATE TABLE plh_plh_plan_horneada (
    plh_id                              BIGINT          NOT NULL IDENTITY(1,1),
    plh_pld_id                          BIGINT          NOT NULL,
    plh_hor_id                          BIGINT          NOT NULL,
    plh_proyeccion                      DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_proyeccion DEFAULT (0),
    plh_pedido_chef                     DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_pedido_chef DEFAULT (0),
    plh_cantidad_hornear                DECIMAL(10,2)   NOT NULL CONSTRAINT DF_plh_cantidad_hornear DEFAULT (0),
    plh_fecha_actualizacion             DATETIME        NOT NULL,
    plh_usuario_actualizacion_codigo    NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_plh PRIMARY KEY (plh_id),
    CONSTRAINT FK_plh_pld FOREIGN KEY (plh_pld_id) REFERENCES plh_pld_plan_detalle (pld_id),
    CONSTRAINT FK_plh_hor FOREIGN KEY (plh_hor_id) REFERENCES plh_hor_horneadas (hor_id),
    CONSTRAINT UQ_plh_detalle_horneada UNIQUE (plh_pld_id, plh_hor_id)
);
GO

-- ─── 8. Pedidos de cocina ─────────────────────────────────────────────────────

CREATE TABLE plh_ped_pedidos_cocina (
    ped_id                      BIGINT          NOT NULL IDENTITY(1,1),
    ped_codigo_neg              NVARCHAR(10)    NOT NULL,
    ped_tienda_codigo           INT             NOT NULL,
    ped_fecha                   DATE            NOT NULL,
    ped_pro_codigo              NVARCHAR(50)    NOT NULL,
    ped_hor_id                  BIGINT          NOT NULL,
    ped_cantidad                DECIMAL(10,2)   NOT NULL CONSTRAINT DF_ped_cantidad DEFAULT (0),
    ped_estado                  NVARCHAR(20)    NOT NULL CONSTRAINT DF_ped_estado DEFAULT ('pendiente'),
    ped_fecha_creacion          DATETIME        NOT NULL,
    ped_usuario_creacion_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_ped PRIMARY KEY (ped_id),
    CONSTRAINT FK_ped_hor FOREIGN KEY (ped_hor_id) REFERENCES plh_hor_horneadas (hor_id),
    CONSTRAINT UQ_ped_fecha_tienda_producto_horneada UNIQUE (ped_fecha, ped_tienda_codigo, ped_codigo_neg, ped_pro_codigo, ped_hor_id)
);
GO

-- ─── 9. Procesos de horneado ──────────────────────────────────────────────────

CREATE TABLE plh_prc_procesos (
    prc_id                      BIGINT          NOT NULL IDENTITY(1,1),
    prc_codigo_neg              NVARCHAR(10)    NOT NULL,
    prc_tienda_codigo           INT             NOT NULL,
    prc_fecha                   DATE            NOT NULL,
    prc_estado                  NVARCHAR(20)    NOT NULL CONSTRAINT DF_prc_estado DEFAULT ('pendiente'),
    prc_fecha_inicio            DATETIME        NULL,
    prc_fecha_fin               DATETIME        NULL,
    prc_usuario_inicio_codigo   NVARCHAR(20)    NULL,
    prc_usuario_fin_codigo      NVARCHAR(20)    NULL,

    CONSTRAINT PK_prc PRIMARY KEY (prc_id),
    CONSTRAINT UQ_prc_fecha_tienda UNIQUE (prc_fecha, prc_tienda_codigo, prc_codigo_neg)
);
GO

-- ─── 10. Proceso horneado — encabezado (por producto/horneada) ───────────────

CREATE TABLE plh_prh_proceso_horneado_encabezado (
    prh_id                              BIGINT          NOT NULL IDENTITY(1,1),
    prh_codigo_neg                      NVARCHAR(10)    NOT NULL,
    prh_tienda_codigo                   INT             NOT NULL,
    prh_prc_id                          BIGINT          NOT NULL,
    prh_pro_codigo                      NVARCHAR(50)    NOT NULL,
    prh_hor_id                          BIGINT          NOT NULL,
    prh_cantidad_bolsas                 DECIMAL(10,2)   NOT NULL CONSTRAINT DF_prh_cantidad_bolsas DEFAULT (0),
    prh_estado_fermentacion             NVARCHAR(20)    NOT NULL CONSTRAINT DF_prh_estado_ferment DEFAULT ('pendiente'),
    prh_fecha_inicio_ferment            DATETIME        NULL,
    prh_fecha_fin_ferment               DATETIME        NULL,
    prh_rack_asignado                   NVARCHAR(20)    NULL,
    prh_temperatura_preheat             DECIMAL(5, 1)   NULL,
    prh_fecha_inicio_horneado           DATETIME        NULL,
    prh_fecha_fin_horneado              DATETIME        NULL,
    prh_observaciones                   NVARCHAR(500)   NULL,
    prh_fecha_actualizacion             DATETIME        NOT NULL,
    prh_usuario_actualizacion_codigo    NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_prh_enc PRIMARY KEY (prh_id),
    CONSTRAINT FK_prh_prc FOREIGN KEY (prh_prc_id) REFERENCES plh_prc_procesos (prc_id),
    CONSTRAINT FK_prh_hor FOREIGN KEY (prh_hor_id) REFERENCES plh_hor_horneadas (hor_id),
    CONSTRAINT UQ_prh_proceso_producto_horneada UNIQUE (prh_prc_id, prh_pro_codigo, prh_hor_id)
);
GO

-- ─── 11. Proceso horneado — detalle (resultado de fermentación) ──────────────

CREATE TABLE plh_prh_proceso_horneado_detalle (
    prh_id                      BIGINT          NOT NULL IDENTITY(1,1),
    prh_prh_id                  BIGINT          NOT NULL,
    prh_cantidad_aceptada       DECIMAL(10,2)   NULL,
    prh_cantidad_rechazada      DECIMAL(10,2)   NULL,
    prh_cantidad_final          DECIMAL(10,2)   NULL,
    prh_fecha_registro          DATETIME        NOT NULL,
    prh_usuario_registro_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_prh_det PRIMARY KEY (prh_id),
    CONSTRAINT FK_prh_det_enc FOREIGN KEY (prh_prh_id) REFERENCES plh_prh_proceso_horneado_encabezado (prh_id)
);
GO

-- ─── 12. Trazabilidad ─────────────────────────────────────────────────────────

CREATE TABLE plh_trz_trazabilidad (
    trz_id              BIGINT          NOT NULL IDENTITY(1,1),
    trz_prh_id          BIGINT          NOT NULL,
    trz_evento_tipo     NVARCHAR(30)    NOT NULL,
    trz_fecha_evento    DATETIME        NOT NULL,
    trz_usuario_codigo  NVARCHAR(20)    NOT NULL,
    trz_observaciones   NVARCHAR(500)   NULL,

    CONSTRAINT PK_trz PRIMARY KEY (trz_id),
    CONSTRAINT FK_trz_prh FOREIGN KEY (trz_prh_id) REFERENCES plh_prh_proceso_horneado_encabezado (prh_id)
);
GO

-- ─── 13. Rotación ─────────────────────────────────────────────────────────────

CREATE TABLE plh_rot_rotacion (
    rot_id                      BIGINT          NOT NULL IDENTITY(1,1),
    rot_codigo_neg              NVARCHAR(10)    NOT NULL,
    rot_tienda_codigo           INT             NOT NULL,
    rot_fecha                   DATE            NOT NULL,
    rot_pro_codigo              NVARCHAR(50)    NOT NULL,
    rot_hor_id                  BIGINT          NOT NULL,
    rot_cantidad_final          DECIMAL(10,2)   NOT NULL CONSTRAINT DF_rot_cantidad DEFAULT (0),
    rot_fecha_registro          DATETIME        NOT NULL,
    rot_usuario_registro_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_rot PRIMARY KEY (rot_id),
    CONSTRAINT FK_rot_hor FOREIGN KEY (rot_hor_id) REFERENCES plh_hor_horneadas (hor_id),
    CONSTRAINT UQ_rot_fecha_tienda_producto_horneada UNIQUE (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_pro_codigo, rot_hor_id)
);
GO

-- ─── 14. Devoluciones ─────────────────────────────────────────────────────────

CREATE TABLE plh_dev_devoluciones (
    dev_id                      BIGINT          NOT NULL IDENTITY(1,1),
    dev_codigo_neg              NVARCHAR(10)    NOT NULL,
    dev_tienda_codigo           INT             NOT NULL,
    dev_fecha_registro          DATE            NOT NULL,
    dev_fecha_venta             DATE            NOT NULL,
    dev_pro_codigo              NVARCHAR(50)    NOT NULL,
    dev_cantidad                DECIMAL(10,2)   NOT NULL CONSTRAINT DF_dev_cantidad DEFAULT (0),
    dev_observaciones           NVARCHAR(500)   NULL,
    dev_dia_cerrado             BIT             NOT NULL CONSTRAINT DF_dev_dia_cerrado DEFAULT (0),
    dev_fecha_creacion          DATETIME        NOT NULL,
    dev_usuario_creacion_codigo NVARCHAR(20)    NOT NULL,

    CONSTRAINT PK_dev PRIMARY KEY (dev_id)
    -- Sin UNIQUE por producto/día: se permiten múltiples registros intra-día.
    -- El cierre de día (dev_dia_cerrado=1) bloquea nuevas entradas.
);
GO
