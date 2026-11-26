-- ============================================================
-- Migración 018 — Reordenar columnas: codigo_neg → tienda_codigo → id
-- Aplica el patrón semántico a 9 tablas del schema plh.
-- Entorno: sm_backoffice_op (desarrollo/test)
-- Prerrequisito: migraciones 000–017 ejecutadas.
-- Advertencia: script destructivo — DROP + RECREATE por tabla.
--              Ejecutar con 0 conexiones activas.
-- ============================================================

BEGIN TRANSACTION;
BEGIN TRY

-- ══════════════════════════════════════════════════════════════
-- PASO 1 — Eliminar FK constraints afectadas
-- ══════════════════════════════════════════════════════════════

-- Desde tablas NO reconstruidas → tablas SÍ reconstruidas
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_log_hor')
    ALTER TABLE plh.plh_log_parametrizacion DROP CONSTRAINT FK_log_hor;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_plh_hor')
    ALTER TABLE plh.plh_plh_plan_horneada DROP CONSTRAINT FK_plh_hor;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pld_pla')
    ALTER TABLE plh.plh_pld_plan_detalle DROP CONSTRAINT FK_pld_pla;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_det_enc')
    ALTER TABLE plh.plh_prh_proceso_horneado_detalle DROP CONSTRAINT FK_prh_det_enc;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_trz_prh')
    ALTER TABLE plh.plh_trz_trazabilidad DROP CONSTRAINT FK_trz_prh;

-- Entre tablas SÍ reconstruidas
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ped_hor')
    ALTER TABLE plh.plh_ped_pedidos_cocina DROP CONSTRAINT FK_ped_hor;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_prc')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado DROP CONSTRAINT FK_prh_prc;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_prh_hor')
    ALTER TABLE plh.plh_prh_proceso_horneado_encabezado DROP CONSTRAINT FK_prh_hor;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_rot_hor')
    ALTER TABLE plh.plh_rot_rotacion DROP CONSTRAINT FK_rot_hor;


-- ══════════════════════════════════════════════════════════════
-- PASO 2 — Reconstruir cada tabla con el nuevo orden de columnas
-- (CREATE tmp → INSERT → DROP original → RENAME → PK/UQ)
-- ══════════════════════════════════════════════════════════════

-- ─── 1. plh_hor_horneadas ────────────────────────────────────

CREATE TABLE plh.plh_hor_horneadas_tmp (
    hor_codigo_neg                  NVARCHAR(10)    NOT NULL,
    hor_tienda_codigo               INT             NOT NULL,
    hor_id                          BIGINT          NOT NULL IDENTITY(1,1),
    hor_numero_secuencia            INT             NOT NULL,
    hor_hora_inicio                 TIME(0)         NOT NULL,
    hor_hora_fin                    TIME(0)         NOT NULL,
    hor_aplica_pedido_cocina        BIT             NOT NULL DEFAULT (1),
    hor_activa                      BIT             NOT NULL DEFAULT (1),
    hor_fecha_creacion              DATETIME        NOT NULL,
    hor_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL,
    hor_fecha_modificacion          DATETIME        NULL,
    hor_usuario_modificacion_codigo NVARCHAR(20)    NULL
);

SET IDENTITY_INSERT plh.plh_hor_horneadas_tmp ON;
INSERT INTO plh.plh_hor_horneadas_tmp
    (hor_id, hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia,
     hor_hora_inicio, hor_hora_fin, hor_aplica_pedido_cocina, hor_activa,
     hor_fecha_creacion, hor_usuario_creacion_codigo,
     hor_fecha_modificacion, hor_usuario_modificacion_codigo)
SELECT
     hor_id, hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia,
     hor_hora_inicio, hor_hora_fin, hor_aplica_pedido_cocina, hor_activa,
     hor_fecha_creacion, hor_usuario_creacion_codigo,
     hor_fecha_modificacion, hor_usuario_modificacion_codigo
FROM plh.plh_hor_horneadas;
SET IDENTITY_INSERT plh.plh_hor_horneadas_tmp OFF;

DROP TABLE plh.plh_hor_horneadas;
EXEC sp_rename 'plh.plh_hor_horneadas_tmp', 'plh_hor_horneadas';

ALTER TABLE plh.plh_hor_horneadas ADD CONSTRAINT PK_hor PRIMARY KEY (hor_id);
CREATE UNIQUE INDEX UQ_hor_tienda_secuencia
    ON plh.plh_hor_horneadas (hor_tienda_codigo, hor_codigo_neg, hor_numero_secuencia);


-- ─── 2. plh_cat_catalogo_productos ───────────────────────────

CREATE TABLE plh.plh_cat_catalogo_productos_tmp (
    cat_codigo_neg                      NVARCHAR(10)    NOT NULL,
    cat_tienda_codigo                   INT             NOT NULL,
    cat_id                              BIGINT          NOT NULL IDENTITY(1,1),
    cat_pro_codigo                      NVARCHAR(50)    NOT NULL,
    cat_tipo                            NVARCHAR(20)    NOT NULL DEFAULT ('regular'),
    cat_factor_conversion               DECIMAL(10,4)   NOT NULL DEFAULT (1),
    cat_activo                          BIT             NOT NULL DEFAULT (1),
    cat_aplica_control_reposteria       BIT             NOT NULL DEFAULT (0),
    cat_aplica_pedido_cocina            BIT             NOT NULL DEFAULT (0),
    cat_estacional                      BIT             NOT NULL DEFAULT (0),
    cat_fecha_creacion                  DATETIME        NOT NULL,
    cat_usuario_creacion_codigo         NVARCHAR(20)    NOT NULL,
    cat_fecha_modificacion              DATETIME        NULL,
    cat_usuario_modificacion_codigo     NVARCHAR(20)    NULL
);

SET IDENTITY_INSERT plh.plh_cat_catalogo_productos_tmp ON;
INSERT INTO plh.plh_cat_catalogo_productos_tmp
    (cat_id, cat_codigo_neg, cat_tienda_codigo, cat_pro_codigo,
     cat_tipo, cat_factor_conversion, cat_activo,
     cat_aplica_control_reposteria, cat_aplica_pedido_cocina, cat_estacional,
     cat_fecha_creacion, cat_usuario_creacion_codigo,
     cat_fecha_modificacion, cat_usuario_modificacion_codigo)
SELECT
     cat_id, cat_codigo_neg, cat_tienda_codigo, cat_pro_codigo,
     cat_tipo, cat_factor_conversion, cat_activo,
     cat_aplica_control_reposteria, cat_aplica_pedido_cocina, cat_estacional,
     cat_fecha_creacion, cat_usuario_creacion_codigo,
     cat_fecha_modificacion, cat_usuario_modificacion_codigo
FROM plh.plh_cat_catalogo_productos;
SET IDENTITY_INSERT plh.plh_cat_catalogo_productos_tmp OFF;

DROP TABLE plh.plh_cat_catalogo_productos;
EXEC sp_rename 'plh.plh_cat_catalogo_productos_tmp', 'plh_cat_catalogo_productos';

ALTER TABLE plh.plh_cat_catalogo_productos ADD CONSTRAINT PK_cat PRIMARY KEY (cat_id);
CREATE UNIQUE INDEX UQ_cat_tienda_producto
    ON plh.plh_cat_catalogo_productos (cat_tienda_codigo, cat_codigo_neg, cat_pro_codigo);


-- ─── 3. plh_mrf_mes_referencia ───────────────────────────────

CREATE TABLE plh.plh_mrf_mes_referencia_tmp (
    mrf_codigo_neg              NVARCHAR(10)    NOT NULL,
    mrf_id                      BIGINT          NOT NULL IDENTITY(1,1),
    mrf_anio                    INT             NOT NULL,
    mrf_mes                     INT             NOT NULL,
    mrf_fecha_creacion          DATETIME        NOT NULL,
    mrf_usuario_creacion_codigo NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_mrf_mes_referencia_tmp ON;
INSERT INTO plh.plh_mrf_mes_referencia_tmp
    (mrf_id, mrf_codigo_neg, mrf_anio, mrf_mes,
     mrf_fecha_creacion, mrf_usuario_creacion_codigo)
SELECT
     mrf_id, mrf_codigo_neg, mrf_anio, mrf_mes,
     mrf_fecha_creacion, mrf_usuario_creacion_codigo
FROM plh.plh_mrf_mes_referencia;
SET IDENTITY_INSERT plh.plh_mrf_mes_referencia_tmp OFF;

DROP TABLE plh.plh_mrf_mes_referencia;
EXEC sp_rename 'plh.plh_mrf_mes_referencia_tmp', 'plh_mrf_mes_referencia';

ALTER TABLE plh.plh_mrf_mes_referencia ADD CONSTRAINT PK_mrf PRIMARY KEY (mrf_id);
CREATE UNIQUE INDEX UQ_mrf_codigo_neg_anio_mes
    ON plh.plh_mrf_mes_referencia (mrf_codigo_neg, mrf_anio, mrf_mes);


-- ─── 4. plh_pla_planes ───────────────────────────────────────

CREATE TABLE plh.plh_pla_planes_tmp (
    pla_codigo_neg                  NVARCHAR(10)    NOT NULL,
    pla_tienda_codigo               INT             NOT NULL,
    pla_id                          BIGINT          NOT NULL IDENTITY(1,1),
    pla_fecha                       DATE            NOT NULL,
    pla_fecha_comparacion           DATE            NOT NULL,
    pla_estado                      TINYINT         NOT NULL DEFAULT (0),
    pla_fecha_generacion            DATETIME        NOT NULL,
    pla_usuario_generacion_codigo   NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_pla_planes_tmp ON;
INSERT INTO plh.plh_pla_planes_tmp
    (pla_id, pla_codigo_neg, pla_tienda_codigo, pla_fecha, pla_fecha_comparacion,
     pla_estado, pla_fecha_generacion, pla_usuario_generacion_codigo)
SELECT
     pla_id, pla_codigo_neg, pla_tienda_codigo, pla_fecha, pla_fecha_comparacion,
     pla_estado, pla_fecha_generacion, pla_usuario_generacion_codigo
FROM plh.plh_pla_planes;
SET IDENTITY_INSERT plh.plh_pla_planes_tmp OFF;

DROP TABLE plh.plh_pla_planes;
EXEC sp_rename 'plh.plh_pla_planes_tmp', 'plh_pla_planes';

ALTER TABLE plh.plh_pla_planes ADD CONSTRAINT PK_pla PRIMARY KEY (pla_id);
CREATE UNIQUE INDEX UQ_pla_fecha_tienda
    ON plh.plh_pla_planes (pla_fecha, pla_tienda_codigo, pla_codigo_neg);


-- ─── 5. plh_ped_pedidos_cocina ───────────────────────────────

CREATE TABLE plh.plh_ped_pedidos_cocina_tmp (
    ped_codigo_neg              NVARCHAR(10)    NOT NULL,
    ped_tienda_codigo           INT             NOT NULL,
    ped_id                      BIGINT          NOT NULL IDENTITY(1,1),
    ped_fecha                   DATE            NOT NULL,
    ped_pro_codigo              NVARCHAR(50)    NOT NULL,
    ped_hor_id                  BIGINT          NOT NULL,
    ped_cantidad                DECIMAL(10,2)   NOT NULL DEFAULT (0),
    ped_estado                  TINYINT         NOT NULL DEFAULT (0),
    ped_fecha_creacion          DATETIME        NOT NULL,
    ped_usuario_creacion_codigo NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_ped_pedidos_cocina_tmp ON;
INSERT INTO plh.plh_ped_pedidos_cocina_tmp
    (ped_id, ped_codigo_neg, ped_tienda_codigo, ped_fecha, ped_pro_codigo,
     ped_hor_id, ped_cantidad, ped_estado,
     ped_fecha_creacion, ped_usuario_creacion_codigo)
SELECT
     ped_id, ped_codigo_neg, ped_tienda_codigo, ped_fecha, ped_pro_codigo,
     ped_hor_id, ped_cantidad, ped_estado,
     ped_fecha_creacion, ped_usuario_creacion_codigo
FROM plh.plh_ped_pedidos_cocina;
SET IDENTITY_INSERT plh.plh_ped_pedidos_cocina_tmp OFF;

DROP TABLE plh.plh_ped_pedidos_cocina;
EXEC sp_rename 'plh.plh_ped_pedidos_cocina_tmp', 'plh_ped_pedidos_cocina';

ALTER TABLE plh.plh_ped_pedidos_cocina ADD CONSTRAINT PK_ped PRIMARY KEY (ped_id);
CREATE UNIQUE INDEX UQ_ped_fecha_tienda_producto_horneada
    ON plh.plh_ped_pedidos_cocina (ped_fecha, ped_tienda_codigo, ped_codigo_neg, ped_pro_codigo, ped_hor_id);


-- ─── 6. plh_prc_procesos ─────────────────────────────────────

CREATE TABLE plh.plh_prc_procesos_tmp (
    prc_codigo_neg              NVARCHAR(10)    NOT NULL,
    prc_tienda_codigo           INT             NOT NULL,
    prc_id                      BIGINT          NOT NULL IDENTITY(1,1),
    prc_fecha                   DATE            NOT NULL,
    prc_estado                  TINYINT         NOT NULL DEFAULT (0),
    prc_fecha_inicio            DATETIME        NULL,
    prc_fecha_fin               DATETIME        NULL,
    prc_usuario_inicio_codigo   NVARCHAR(20)    NULL,
    prc_usuario_fin_codigo      NVARCHAR(20)    NULL,
    prc_estado_rotacion         NVARCHAR(20)    NOT NULL DEFAULT ('PENDIENTE'),
    prc_fecha_cierre_rotacion   DATETIME        NULL,
    prc_usuario_cierre_rotacion NVARCHAR(50)    NULL
);

SET IDENTITY_INSERT plh.plh_prc_procesos_tmp ON;
INSERT INTO plh.plh_prc_procesos_tmp
    (prc_id, prc_codigo_neg, prc_tienda_codigo, prc_fecha, prc_estado,
     prc_fecha_inicio, prc_fecha_fin,
     prc_usuario_inicio_codigo, prc_usuario_fin_codigo,
     prc_estado_rotacion, prc_fecha_cierre_rotacion, prc_usuario_cierre_rotacion)
SELECT
     prc_id, prc_codigo_neg, prc_tienda_codigo, prc_fecha, prc_estado,
     prc_fecha_inicio, prc_fecha_fin,
     prc_usuario_inicio_codigo, prc_usuario_fin_codigo,
     prc_estado_rotacion, prc_fecha_cierre_rotacion, prc_usuario_cierre_rotacion
FROM plh.plh_prc_procesos;
SET IDENTITY_INSERT plh.plh_prc_procesos_tmp OFF;

DROP TABLE plh.plh_prc_procesos;
EXEC sp_rename 'plh.plh_prc_procesos_tmp', 'plh_prc_procesos';

ALTER TABLE plh.plh_prc_procesos ADD CONSTRAINT PK_prc PRIMARY KEY (prc_id);
CREATE UNIQUE INDEX UQ_prc_fecha_tienda
    ON plh.plh_prc_procesos (prc_fecha, prc_tienda_codigo, prc_codigo_neg);


-- ─── 7. plh_prh_proceso_horneado_encabezado ──────────────────
-- Columnas finales post-mig 010, 014, 016, 017

CREATE TABLE plh.plh_prh_proceso_horneado_encabezado_tmp (
    prh_codigo_neg                      NVARCHAR(10)    NOT NULL,
    prh_tienda_codigo                   INT             NOT NULL,
    prh_id                              BIGINT          NOT NULL IDENTITY(1,1),
    prh_prc_id                          BIGINT          NOT NULL,
    prh_pro_codigo                      NVARCHAR(50)    NOT NULL,
    prh_hor_id                          BIGINT          NOT NULL,
    prh_cantidad_bolsas                 DECIMAL(10,2)   NOT NULL DEFAULT (0),
    prh_estado_fermentacion             TINYINT         NOT NULL DEFAULT (0),
    prh_fecha_inicio_ferment            DATETIME        NULL,
    prh_fecha_fin_ferment               DATETIME        NULL,
    prh_rack_asignado                   NVARCHAR(20)    NULL,
    prh_temperatura_preheat             DECIMAL(5,1)    NULL,
    prh_temperatura_preheat_2           DECIMAL(5,1)    NULL,
    prh_temperatura_horno               DECIMAL(5,1)    NULL,
    prh_temperatura_horno_2             DECIMAL(5,1)    NULL,
    prh_vapor_segundos                  INT             NULL,
    prh_omitio_fermentacion             BIT             NOT NULL DEFAULT (0),
    prh_temperatura_descongelamiento    DECIMAL(5,1)    NULL,
    prh_fecha_inicio_horneado           DATETIME        NULL,
    prh_fecha_fin_horneado              DATETIME        NULL,
    prh_observaciones                   NVARCHAR(500)   NULL,
    prh_revisado                        BIT             NOT NULL DEFAULT (0),
    prh_fecha_revision                  DATETIME        NULL,
    prh_usuario_revision_codigo         NVARCHAR(50)    NULL,
    prh_fecha_actualizacion             DATETIME        NOT NULL,
    prh_usuario_actualizacion_codigo    NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_prh_proceso_horneado_encabezado_tmp ON;
INSERT INTO plh.plh_prh_proceso_horneado_encabezado_tmp
    (prh_id, prh_codigo_neg, prh_tienda_codigo, prh_prc_id, prh_pro_codigo, prh_hor_id,
     prh_cantidad_bolsas, prh_estado_fermentacion,
     prh_fecha_inicio_ferment, prh_fecha_fin_ferment,
     prh_rack_asignado,
     prh_temperatura_preheat, prh_temperatura_preheat_2,
     prh_temperatura_horno, prh_temperatura_horno_2,
     prh_vapor_segundos, prh_omitio_fermentacion, prh_temperatura_descongelamiento,
     prh_fecha_inicio_horneado, prh_fecha_fin_horneado,
     prh_observaciones,
     prh_revisado, prh_fecha_revision, prh_usuario_revision_codigo,
     prh_fecha_actualizacion, prh_usuario_actualizacion_codigo)
SELECT
     prh_id, prh_codigo_neg, prh_tienda_codigo, prh_prc_id, prh_pro_codigo, prh_hor_id,
     prh_cantidad_bolsas, prh_estado_fermentacion,
     prh_fecha_inicio_ferment, prh_fecha_fin_ferment,
     prh_rack_asignado,
     prh_temperatura_preheat, prh_temperatura_preheat_2,
     prh_temperatura_horno, prh_temperatura_horno_2,
     prh_vapor_segundos, prh_omitio_fermentacion, prh_temperatura_descongelamiento,
     prh_fecha_inicio_horneado, prh_fecha_fin_horneado,
     prh_observaciones,
     prh_revisado, prh_fecha_revision, prh_usuario_revision_codigo,
     prh_fecha_actualizacion, prh_usuario_actualizacion_codigo
FROM plh.plh_prh_proceso_horneado_encabezado;
SET IDENTITY_INSERT plh.plh_prh_proceso_horneado_encabezado_tmp OFF;

DROP TABLE plh.plh_prh_proceso_horneado_encabezado;
EXEC sp_rename 'plh.plh_prh_proceso_horneado_encabezado_tmp', 'plh_prh_proceso_horneado_encabezado';

ALTER TABLE plh.plh_prh_proceso_horneado_encabezado ADD CONSTRAINT PK_prh_enc PRIMARY KEY (prh_id);
CREATE UNIQUE INDEX UQ_prh_proceso_producto_horneada
    ON plh.plh_prh_proceso_horneado_encabezado (prh_prc_id, prh_pro_codigo, prh_hor_id);


-- ─── 8. plh_rot_rotacion ─────────────────────────────────────
-- Columnas finales post-mig 016 (rot_hor_id nullable, rot_es_transferencia)

CREATE TABLE plh.plh_rot_rotacion_tmp (
    rot_codigo_neg              NVARCHAR(10)    NOT NULL,
    rot_tienda_codigo           INT             NOT NULL,
    rot_id                      BIGINT          NOT NULL IDENTITY(1,1),
    rot_fecha                   DATE            NOT NULL,
    rot_pro_codigo              NVARCHAR(50)    NOT NULL,
    rot_hor_id                  BIGINT          NULL,
    rot_es_transferencia        BIT             NOT NULL DEFAULT (0),
    rot_cantidad_final          DECIMAL(10,2)   NOT NULL DEFAULT (0),
    rot_fecha_registro          DATETIME        NOT NULL,
    rot_usuario_registro_codigo NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_rot_rotacion_tmp ON;
INSERT INTO plh.plh_rot_rotacion_tmp
    (rot_id, rot_codigo_neg, rot_tienda_codigo, rot_fecha, rot_pro_codigo,
     rot_hor_id, rot_es_transferencia, rot_cantidad_final,
     rot_fecha_registro, rot_usuario_registro_codigo)
SELECT
     rot_id, rot_codigo_neg, rot_tienda_codigo, rot_fecha, rot_pro_codigo,
     rot_hor_id, rot_es_transferencia, rot_cantidad_final,
     rot_fecha_registro, rot_usuario_registro_codigo
FROM plh.plh_rot_rotacion;
SET IDENTITY_INSERT plh.plh_rot_rotacion_tmp OFF;

DROP TABLE plh.plh_rot_rotacion;
EXEC sp_rename 'plh.plh_rot_rotacion_tmp', 'plh_rot_rotacion';

ALTER TABLE plh.plh_rot_rotacion ADD CONSTRAINT PK_rot PRIMARY KEY (rot_id);
CREATE UNIQUE INDEX UQ_rot_fecha_tienda_producto_horneada
    ON plh.plh_rot_rotacion (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_pro_codigo, rot_hor_id)
    WHERE rot_hor_id IS NOT NULL;
CREATE INDEX IX_rot_transferencias
    ON plh.plh_rot_rotacion (rot_fecha, rot_tienda_codigo, rot_codigo_neg, rot_es_transferencia)
    WHERE rot_es_transferencia = 1;


-- ─── 9. plh_dev_devoluciones ─────────────────────────────────
-- Columnas finales post-mig 001, 005, 011, 015

CREATE TABLE plh.plh_dev_devoluciones_tmp (
    dev_codigo_neg                  NVARCHAR(10)    NOT NULL,
    dev_tienda_codigo               INT             NOT NULL,
    dev_id                          BIGINT          NOT NULL IDENTITY(1,1),
    dev_fecha_registro              DATE            NOT NULL,
    dev_fecha_venta                 DATE            NOT NULL,
    dev_pro_codigo                  NVARCHAR(50)    NOT NULL,
    dev_hor_id                      BIGINT          NULL,
    dev_cantidad                    DECIMAL(10,2)   NOT NULL DEFAULT (0),
    dev_observaciones               NVARCHAR(500)   NULL,
    dev_estado                      TINYINT         NOT NULL DEFAULT (0),
    dev_usuario_autorizacion        NVARCHAR(50)    NULL,
    dev_fecha_autorizacion          DATETIME        NULL,
    dev_dia_cerrado                 BIT             NOT NULL DEFAULT (0),
    dev_fecha_creacion              DATETIME        NOT NULL,
    dev_usuario_creacion_codigo     NVARCHAR(20)    NOT NULL
);

SET IDENTITY_INSERT plh.plh_dev_devoluciones_tmp ON;
INSERT INTO plh.plh_dev_devoluciones_tmp
    (dev_id, dev_codigo_neg, dev_tienda_codigo,
     dev_fecha_registro, dev_fecha_venta, dev_pro_codigo, dev_hor_id,
     dev_cantidad, dev_observaciones,
     dev_estado, dev_usuario_autorizacion, dev_fecha_autorizacion,
     dev_dia_cerrado, dev_fecha_creacion, dev_usuario_creacion_codigo)
SELECT
     dev_id, dev_codigo_neg, dev_tienda_codigo,
     dev_fecha_registro, dev_fecha_venta, dev_pro_codigo, dev_hor_id,
     dev_cantidad, dev_observaciones,
     dev_estado, dev_usuario_autorizacion, dev_fecha_autorizacion,
     dev_dia_cerrado, dev_fecha_creacion, dev_usuario_creacion_codigo
FROM plh.plh_dev_devoluciones;
SET IDENTITY_INSERT plh.plh_dev_devoluciones_tmp OFF;

DROP TABLE plh.plh_dev_devoluciones;
EXEC sp_rename 'plh.plh_dev_devoluciones_tmp', 'plh_dev_devoluciones';

ALTER TABLE plh.plh_dev_devoluciones ADD CONSTRAINT PK_dev PRIMARY KEY (dev_id);


-- ══════════════════════════════════════════════════════════════
-- PASO 3 — Recrear FK constraints
-- ══════════════════════════════════════════════════════════════

-- plh_log_parametrizacion → plh_hor_horneadas
ALTER TABLE plh.plh_log_parametrizacion
    ADD CONSTRAINT FK_log_hor FOREIGN KEY (log_hor_id)
    REFERENCES plh.plh_hor_horneadas (hor_id);

-- plh_plh_plan_horneada → plh_hor_horneadas
ALTER TABLE plh.plh_plh_plan_horneada
    ADD CONSTRAINT FK_plh_hor FOREIGN KEY (plh_hor_id)
    REFERENCES plh.plh_hor_horneadas (hor_id);

-- plh_pld_plan_detalle → plh_pla_planes
ALTER TABLE plh.plh_pld_plan_detalle
    ADD CONSTRAINT FK_pld_pla FOREIGN KEY (pld_pla_id)
    REFERENCES plh.plh_pla_planes (pla_id);

-- plh_ped_pedidos_cocina → plh_hor_horneadas
ALTER TABLE plh.plh_ped_pedidos_cocina
    ADD CONSTRAINT FK_ped_hor FOREIGN KEY (ped_hor_id)
    REFERENCES plh.plh_hor_horneadas (hor_id);

-- plh_prc_procesos: sin FKs salientes

-- plh_prh_proceso_horneado_encabezado → plh_prc_procesos + plh_hor_horneadas
ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
    ADD CONSTRAINT FK_prh_prc FOREIGN KEY (prh_prc_id)
    REFERENCES plh.plh_prc_procesos (prc_id);

ALTER TABLE plh.plh_prh_proceso_horneado_encabezado
    ADD CONSTRAINT FK_prh_hor FOREIGN KEY (prh_hor_id)
    REFERENCES plh.plh_hor_horneadas (hor_id);

-- plh_prh_proceso_horneado_detalle → plh_prh_proceso_horneado_encabezado
ALTER TABLE plh.plh_prh_proceso_horneado_detalle
    ADD CONSTRAINT FK_prh_det_enc FOREIGN KEY (prh_prh_id)
    REFERENCES plh.plh_prh_proceso_horneado_encabezado (prh_id);

-- plh_trz_trazabilidad → plh_prh_proceso_horneado_encabezado
ALTER TABLE plh.plh_trz_trazabilidad
    ADD CONSTRAINT FK_trz_prh FOREIGN KEY (trz_prh_id)
    REFERENCES plh.plh_prh_proceso_horneado_encabezado (prh_id);

-- plh_rot_rotacion → plh_hor_horneadas (nullable)
ALTER TABLE plh.plh_rot_rotacion
    ADD CONSTRAINT FK_rot_hor FOREIGN KEY (rot_hor_id)
    REFERENCES plh.plh_hor_horneadas (hor_id);


-- ══════════════════════════════════════════════════════════════
-- PASO 4 — Restaurar permisos
-- ══════════════════════════════════════════════════════════════

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::plh TO [Plh_app_user];

COMMIT TRANSACTION;
PRINT 'Migración 018 completada exitosamente.';

END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR('Migración 018 revertida. Error: %s', 16, 1, @err);
END CATCH
GO
