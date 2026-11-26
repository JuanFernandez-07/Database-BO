-- =============================================
-- Migración: 020_RecreateCatalogo_AddProNombre
-- Descripción: Dropea y recrea plh_cat_catalogo_productos agregando
--              cat_pro_nombre (NVARCHAR 255) inmediatamente después de
--              cat_pro_codigo, con todas las columnas en orden lógico.
-- Entorno: Desarrollo (sin datos productivos)
-- Fecha: 2026-05-15
-- =============================================

DROP TABLE IF EXISTS [plh].[plh_cat_catalogo_productos];
GO

CREATE TABLE [plh].[plh_cat_catalogo_productos] (
    cat_id                              BIGINT          NOT NULL IDENTITY(1,1),
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
    cat_fecha_creacion                  DATETIME        NOT NULL,
    cat_usuario_creacion_codigo         NVARCHAR(20)    NOT NULL,
    cat_fecha_modificacion              DATETIME        NULL,
    cat_usuario_modificacion_codigo     NVARCHAR(20)    NULL,

    CONSTRAINT PK_cat PRIMARY KEY (cat_id),
    CONSTRAINT UQ_cat_tienda_producto UNIQUE (cat_tienda_codigo, cat_codigo_neg, cat_pro_codigo)
);
GO
