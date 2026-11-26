-- =============================================
-- Script: 001_Create_pyl_Schema_Tables
-- Módulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripción: Crea el schema pyl (compartido con pyl.pve_proyeccion_venta) y
--              todas las tablas del módulo: pyl.prg_*.
--              Idempotente: seguro de re-ejecutar.
-- Base: sm_backoffice
-- Fecha: 2026-09-02
-- =============================================

USE [sm_backoffice];
GO

-- ─── 0. Schema ───────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'pyl')
    EXEC('CREATE SCHEMA pyl');
GO

-- ─── 1. Reportes ─────────────────────────────────────────────────────────────
-- rep_id_negocio es FK conceptual a la tabla de Negocio existente (fuera de
-- este schema — no se crea ni se referencia con constraint física aquí).

IF OBJECT_ID('pyl.prg_rep_reporte', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_rep_reporte] (
        rep_id_negocio  INT             NOT NULL,
        rep_id_reporte  INT             NOT NULL,
        rep_nombre      NVARCHAR(150)   NOT NULL,
        rep_id_estado   TINYINT         NOT NULL CONSTRAINT DF_prg_rep_id_estado DEFAULT (1),

        CONSTRAINT PK_prg_rep PRIMARY KEY (rep_id_negocio, rep_id_reporte),
        CONSTRAINT CK_prg_rep_id_estado CHECK (rep_id_estado IN (0, 1))
    );
END
GO

-- ─── 2. Rubro Grupo ──────────────────────────────────────────────────────────

IF OBJECT_ID('pyl.prg_rgp_rubro_grupo', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_rgp_rubro_grupo] (
        rgp_id_negocio  INT             NOT NULL,
        rgp_id_reporte  INT             NOT NULL,
        rgp_id_grupo    INT             NOT NULL,
        rgp_nombre      NVARCHAR(150)   NOT NULL,
        rgp_id_estado   TINYINT         NOT NULL CONSTRAINT DF_prg_rgp_id_estado DEFAULT (1),

        CONSTRAINT PK_prg_rgp PRIMARY KEY (rgp_id_negocio, rgp_id_reporte, rgp_id_grupo),
        CONSTRAINT CK_prg_rgp_id_estado CHECK (rgp_id_estado IN (0, 1)),
        CONSTRAINT FK_prg_rgp_rep FOREIGN KEY (rgp_id_negocio, rgp_id_reporte)
            REFERENCES [pyl].[prg_rep_reporte] (rep_id_negocio, rep_id_reporte)
    );
END
GO

-- ─── 3. Rubros ───────────────────────────────────────────────────────────────

IF OBJECT_ID('pyl.prg_rub_rubro', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_rub_rubro] (
        rub_id_negocio  INT             NOT NULL,
        rub_id_reporte  INT             NOT NULL,
        rub_id_rubro    INT             NOT NULL,
        rub_nombre      NVARCHAR(150)   NOT NULL,
        rub_tipo_dato   TINYINT         NOT NULL,   -- 1-Venta, 2-Calculo, 3-Porcentaje, 4-Monto
        rub_aplica_menu TINYINT         NOT NULL CONSTRAINT DF_prg_rub_aplica_menu DEFAULT (0),  -- 1-SI, 0-NO
        rub_id_grupo    INT             NULL,       -- opcional
        rub_orden       INT             NOT NULL CONSTRAINT DF_prg_rub_orden DEFAULT (0),
        rub_id_estado   TINYINT         NOT NULL CONSTRAINT DF_prg_rub_id_estado DEFAULT (1),

        CONSTRAINT PK_prg_rub PRIMARY KEY (rub_id_negocio, rub_id_reporte, rub_id_rubro),
        CONSTRAINT CK_prg_rub_tipo_dato CHECK (rub_tipo_dato IN (1, 2, 3, 4)),
        CONSTRAINT CK_prg_rub_aplica_menu CHECK (rub_aplica_menu IN (0, 1)),
        CONSTRAINT CK_prg_rub_id_estado CHECK (rub_id_estado IN (0, 1)),
        CONSTRAINT FK_prg_rub_rep FOREIGN KEY (rub_id_negocio, rub_id_reporte)
            REFERENCES [pyl].[prg_rep_reporte] (rep_id_negocio, rep_id_reporte),
        -- FK compuesta opcional: si rub_id_grupo es NULL, la constraint no aplica
        CONSTRAINT FK_prg_rub_rgp FOREIGN KEY (rub_id_negocio, rub_id_reporte, rub_id_grupo)
            REFERENCES [pyl].[prg_rgp_rubro_grupo] (rgp_id_negocio, rgp_id_reporte, rgp_id_grupo)
    );
END
GO

-- ─── 4. Rubro Menú ───────────────────────────────────────────────────────────
-- Desglose de un rubro (ej. Costo de Comida) por línea de menú/categoría —
-- solo el catálogo; el tipo de dato lo hereda del rubro padre (rub_tipo_dato).

IF OBJECT_ID('pyl.prg_rbm_rubro_menu', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_rbm_rubro_menu] (
        rbm_id_negocio    INT             NOT NULL,
        rbm_id_reporte    INT             NOT NULL,
        rbm_id_rubro      INT             NOT NULL,
        rbm_id_rubromenu  INT             NOT NULL,
        rbm_nombre        NVARCHAR(150)   NOT NULL,
        rbm_orden         INT             NOT NULL CONSTRAINT DF_prg_rbm_orden DEFAULT (0),
        rbm_id_estado     TINYINT         NOT NULL CONSTRAINT DF_prg_rbm_id_estado DEFAULT (1),

        CONSTRAINT PK_prg_rbm PRIMARY KEY (rbm_id_negocio, rbm_id_reporte, rbm_id_rubro, rbm_id_rubromenu),
        CONSTRAINT CK_prg_rbm_id_estado CHECK (rbm_id_estado IN (0, 1)),
        CONSTRAINT FK_prg_rbm_rub FOREIGN KEY (rbm_id_negocio, rbm_id_reporte, rbm_id_rubro)
            REFERENCES [pyl].[prg_rub_rubro] (rub_id_negocio, rub_id_reporte, rub_id_rubro)
    );
END
GO

-- ─── 5. Rubro Cálculo ────────────────────────────────────────────────────────
-- Autoreferencia doble a prg_rub_rubro: rbc_id_rubro = el rubro tipo Cálculo;
-- rbc_id_rubro_referencia = cada rubro componente, sumado/restado según signo_operacion.
-- NOTA: signo_operacion es SMALLINT (no TINYINT) porque TINYINT en SQL Server
-- es sin signo (0-255) y no admite -1.

IF OBJECT_ID('pyl.prg_rbc_rubro_calculo', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_rbc_rubro_calculo] (
        rbc_id_negocio          INT       NOT NULL,
        rbc_id_reporte          INT       NOT NULL,
        rbc_id_rubro            INT       NOT NULL,
        rbc_id_rubro_referencia INT       NOT NULL,
        rbc_signo_operacion     SMALLINT  NOT NULL,   -- 1, -1
        rbc_id_estado           TINYINT   NOT NULL CONSTRAINT DF_prg_rbc_id_estado DEFAULT (1),

        CONSTRAINT PK_prg_rbc PRIMARY KEY (rbc_id_negocio, rbc_id_reporte, rbc_id_rubro, rbc_id_rubro_referencia),
        CONSTRAINT CK_prg_rbc_signo_operacion CHECK (rbc_signo_operacion IN (1, -1)),
        CONSTRAINT CK_prg_rbc_id_estado CHECK (rbc_id_estado IN (0, 1)),
        CONSTRAINT CK_prg_rbc_no_autorreferencia CHECK (rbc_id_rubro <> rbc_id_rubro_referencia),
        CONSTRAINT FK_prg_rbc_rub FOREIGN KEY (rbc_id_negocio, rbc_id_reporte, rbc_id_rubro)
            REFERENCES [pyl].[prg_rub_rubro] (rub_id_negocio, rub_id_reporte, rub_id_rubro),
        CONSTRAINT FK_prg_rbc_rub_referencia FOREIGN KEY (rbc_id_negocio, rbc_id_reporte, rbc_id_rubro_referencia)
            REFERENCES [pyl].[prg_rub_rubro] (rub_id_negocio, rub_id_reporte, rub_id_rubro)
    );
END
GO

-- ─── 6. Plan Encabezado ──────────────────────────────────────────────────────
-- El presupuesto SÍ se captura por tienda (confirmado con negocio) — a
-- diferencia del catálogo (rubros/grupos/menú/cálculo), que es compartido por
-- todas las tiendas de un mismo negocio.

IF OBJECT_ID('pyl.prg_pen_plan_encabezado', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_pen_plan_encabezado] (
        pen_id_negocio    INT           NOT NULL,
        pen_id_reporte    INT           NOT NULL,
        pen_tienda_codigo INT           NOT NULL,
        pen_anio          INT           NOT NULL,
        pen_nombre        NVARCHAR(150) NOT NULL,
        pen_anio_anterior INT           NULL,

        CONSTRAINT PK_prg_pen PRIMARY KEY (pen_id_negocio, pen_id_reporte, pen_tienda_codigo, pen_anio),
        CONSTRAINT FK_prg_pen_rep FOREIGN KEY (pen_id_negocio, pen_id_reporte)
            REFERENCES [pyl].[prg_rep_reporte] (rep_id_negocio, rep_id_reporte)
    );
END
GO

-- ─── 7. Plan Detalle ─────────────────────────────────────────────────────────
-- Solo valores por tienda/mes — la metadata (nombre, tipo_dato, aplica_menu) ya
-- vive en prg_rub_rubro (compartido por negocio) y se obtiene por JOIN, no se duplica aquí.
-- Excepción: pld_orden SÍ se denormaliza (ver 010_Add_PldOrden_PlanDetalle.sql)
-- para que reportes/consultas SQL directas puedan ordenar sin JOIN — mismo
-- patrón que pyl.vta_rme_reporte_mes.rme_orden.
-- pld_monto/pld_pct: lo que el usuario captura (según rub_tipo_dato del rubro).
-- pld_base_monto/pld_base_pct: snapshot de la Venta usada como base del % en el
-- momento del cálculo (para no recalcular históricos si la Venta se ajusta después).

IF OBJECT_ID('pyl.prg_pld_plan_detalle', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_pld_plan_detalle] (
        pld_id_negocio      INT             NOT NULL,
        pld_id_reporte      INT             NOT NULL,
        pld_tienda_codigo   INT             NOT NULL,
        pld_anio            INT             NOT NULL,
        pld_mes             TINYINT         NOT NULL,
        pld_id_rubro        INT             NOT NULL,
        pld_monto           DECIMAL(18, 2)  NOT NULL CONSTRAINT DF_prg_pld_monto DEFAULT (0),
        pld_pct             DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pld_pct DEFAULT (0),
        pld_pct_ly          DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pld_pct_ly DEFAULT (0),
        pld_pct_diferencia  DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pld_pct_diferencia DEFAULT (0),
        pld_base_monto      DECIMAL(18, 2)  NOT NULL CONSTRAINT DF_prg_pld_base_monto DEFAULT (0),
        pld_base_pct        DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pld_base_pct DEFAULT (0),
        pld_orden           INT             NOT NULL CONSTRAINT DF_prg_pld_orden DEFAULT (0),

        CONSTRAINT PK_prg_pld PRIMARY KEY (pld_id_negocio, pld_id_reporte, pld_tienda_codigo, pld_anio, pld_mes, pld_id_rubro),
        CONSTRAINT CK_prg_pld_mes CHECK (pld_mes BETWEEN 1 AND 12),
        CONSTRAINT FK_prg_pld_rub FOREIGN KEY (pld_id_negocio, pld_id_reporte, pld_id_rubro)
            REFERENCES [pyl].[prg_rub_rubro] (rub_id_negocio, rub_id_reporte, rub_id_rubro),
        CONSTRAINT FK_prg_pld_pen FOREIGN KEY (pld_id_negocio, pld_id_reporte, pld_tienda_codigo, pld_anio)
            REFERENCES [pyl].[prg_pen_plan_encabezado] (pen_id_negocio, pen_id_reporte, pen_tienda_codigo, pen_anio)
    );
END
GO

-- ─── 8. Plan Detalle Menú ────────────────────────────────────────────────────
-- Igual que Plan Detalle: solo valores, sin duplicar metadata (esa vive en
-- prg_rbm_rubro_menu, compartido por negocio). No lleva mes/año/tienda propios en
-- el catálogo de referencia — se guarda un valor por tienda/mes vía la
-- combinación con prg_pld_plan_detalle (mismo negocio/reporte/tienda/año/mes/rubro).

IF OBJECT_ID('pyl.prg_pdm_plan_detalle_menu', 'U') IS NULL
BEGIN
    CREATE TABLE [pyl].[prg_pdm_plan_detalle_menu] (
        pdm_id_negocio    INT             NOT NULL,
        pdm_id_reporte    INT             NOT NULL,
        pdm_tienda_codigo INT             NOT NULL,
        pdm_anio          INT             NOT NULL,
        pdm_mes           TINYINT         NOT NULL,
        pdm_id_rubro      INT             NOT NULL,
        pdm_id_rubromenu  INT             NOT NULL,
        pdm_monto         DECIMAL(18, 2)  NOT NULL CONSTRAINT DF_prg_pdm_monto DEFAULT (0),
        pdm_pct           DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pdm_pct DEFAULT (0),
        pdm_pct_ly        DECIMAL(9, 4)   NOT NULL CONSTRAINT DF_prg_pdm_pct_ly DEFAULT (0),

        CONSTRAINT PK_prg_pdm PRIMARY KEY (pdm_id_negocio, pdm_id_reporte, pdm_tienda_codigo, pdm_anio, pdm_mes, pdm_id_rubro, pdm_id_rubromenu),
        CONSTRAINT CK_prg_pdm_mes CHECK (pdm_mes BETWEEN 1 AND 12),
        CONSTRAINT FK_prg_pdm_rbm FOREIGN KEY (pdm_id_negocio, pdm_id_reporte, pdm_id_rubro, pdm_id_rubromenu)
            REFERENCES [pyl].[prg_rbm_rubro_menu] (rbm_id_negocio, rbm_id_reporte, rbm_id_rubro, rbm_id_rubromenu),
        CONSTRAINT FK_prg_pdm_pld FOREIGN KEY (pdm_id_negocio, pdm_id_reporte, pdm_tienda_codigo, pdm_anio, pdm_mes, pdm_id_rubro)
            REFERENCES [pyl].[prg_pld_plan_detalle] (pld_id_negocio, pld_id_reporte, pld_tienda_codigo, pld_anio, pld_mes, pld_id_rubro)
    );
END
GO
