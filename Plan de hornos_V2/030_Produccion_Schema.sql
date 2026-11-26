-- =============================================
-- CR-20260816-01 Devolución Cocina — DEPLOY A PRODUCCIÓN, parte 1 de 3: SCHEMA
--
-- Consolida en un solo script, ya en su forma FINAL (no reproduce el historial
-- de versiones intermedias que se usó en desarrollo — 025 creó una tabla V1 en
-- forma de ledger y 027 la reemplazó por esta V2 por horneada; producción
-- nunca tuvo la V1, así que aquí se crea directo en su forma definitiva):
--
--   1) Tabla nueva  plh.plh_rec_recepciones_chef       (Recepción del chef, por horneada)
--   2) Columna nueva plh_dev_devoluciones.dev_origen_cocina      (BIT, default 0)
--   3) Columna nueva plh_dev_devoluciones.dev_hor_numero_secuencia (INT NULL)
--
-- Idempotente — seguro de correr más de una vez. Orden de deploy: este archivo
-- primero, luego 031_Produccion_StoredProcedures_RecepcionChef.sql, luego
-- Database/sm_backoffice_op/StoredProceduresFinal/07_Devolucion.sql (ya
-- actualizado y validado en Plan de hornos_V2/07_Devolucion.sql).
-- =============================================

USE [sm_backoffice_op];
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ─── 1) Recepción del chef, por horneada ─────────────────────────────────
    -- Espejo de plh_prh_proceso_horneado_detalle: una fila por producto ×
    -- horneada × día, UPSERT (no ledger). Aceptado = Pedido Chef + ADD/FAL
    -- (CR-20260911-01) — ADD/FAL admite negativos (faltante) y positivos
    -- (adicional); el motivo solo es obligatorio cuando es negativo.
    IF OBJECT_ID('plh.plh_rec_recepciones_chef', 'U') IS NULL
    BEGIN
        CREATE TABLE [plh].[plh_rec_recepciones_chef] (
            rec_codigo_neg               NVARCHAR(10)    NOT NULL,
            rec_tienda_codigo            INT             NOT NULL,
            rec_fecha                    DATE            NOT NULL,
            rec_pro_codigo               NVARCHAR(50)    NOT NULL,
            rec_hor_numero_secuencia     INT             NOT NULL,
            rec_cantidad_aceptada        DECIMAL(10,2)   NULL,
            rec_cantidad_add_fal         DECIMAL(10,2)   NULL,
            rec_motivo_rechazo           NVARCHAR(200)   NULL,
            rec_revisado                 BIT             NOT NULL CONSTRAINT DF_rec_revisado DEFAULT (0),
            rec_fecha_revision           DATETIME        NULL,
            rec_usuario_revision_codigo  NVARCHAR(50)    NULL,
            rec_fecha_registro           DATETIME        NOT NULL,
            rec_usuario_registro_codigo  NVARCHAR(20)    NOT NULL,

            CONSTRAINT PK_rec PRIMARY KEY (rec_codigo_neg, rec_tienda_codigo, rec_fecha, rec_pro_codigo, rec_hor_numero_secuencia),
            CONSTRAINT FK_rec_hor FOREIGN KEY (rec_codigo_neg, rec_tienda_codigo, rec_hor_numero_secuencia)
                REFERENCES [plh].[plh_hor_horneadas] (hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia)
        );

        GRANT SELECT, INSERT, UPDATE, DELETE ON [plh].[plh_rec_recepciones_chef] TO [Plh_app_user];
    END

    -- ─── 1b) Migración: rename ADD/FAL en tabla ya existente (CR-20260911-01) ─
    -- Si esta tabla ya se había creado con el nombre viejo (rec_cantidad_rechazada,
    -- antes de este CR) el CREATE TABLE de arriba no corre — hay que renombrar
    -- la columna en la tabla existente.
    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('plh.plh_rec_recepciones_chef')
          AND name = 'rec_cantidad_rechazada'
    )
    AND NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('plh.plh_rec_recepciones_chef')
          AND name = 'rec_cantidad_add_fal'
    )
    BEGIN
        EXEC sp_rename 'plh.plh_rec_recepciones_chef.rec_cantidad_rechazada', 'rec_cantidad_add_fal', 'COLUMN';
    END

    -- ─── 2) Discriminador de origen en devoluciones ──────────────────────────
    -- Default 0 preserva el comportamiento actual (General/Repostería) intacto;
    -- las filas de "Devolución Cocina" llegan en 1.
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('plh.plh_dev_devoluciones')
          AND name = 'dev_origen_cocina'
    )
    BEGIN
        ALTER TABLE [plh].[plh_dev_devoluciones]
            ADD dev_origen_cocina BIT NOT NULL CONSTRAINT DF_dev_origen_cocina DEFAULT (0);
    END

    -- ─── 3) Horneada asociada a la devolución ────────────────────────────────
    -- NULL para lo histórico/general (sin horneada); con valor para líneas de
    -- repostería/cocina registradas por horneada.
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('plh.plh_dev_devoluciones')
          AND name = 'dev_hor_numero_secuencia'
    )
    BEGIN
        ALTER TABLE plh.plh_dev_devoluciones
            ADD dev_hor_numero_secuencia INT NULL;
    END

    COMMIT TRANSACTION;
    PRINT 'CR-20260816-01: schema de producción aplicado exitosamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
