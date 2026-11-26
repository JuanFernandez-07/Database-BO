-- =============================================
-- Migration 022: Catálogo de tipos de evento + migración trz_evento_tipo → trz_tip_id
-- Idempotente: seguro de re-ejecutar
-- =============================================

USE [sm_backoffice_op];
GO

-- ─── 1. Tabla catálogo de tipos de evento ────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('plh.plh_tip_tipos_evento'))
BEGIN
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
END;
GO

GRANT SELECT ON [plh].[plh_tip_tipos_evento] TO [Plh_app_user];
GO

-- ─── 2. Migrar plh_trz_trazabilidad: trz_evento_tipo → trz_tip_id ────────────

-- 2a. Agregar columna nueva nullable
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_tip_id'
)
    ALTER TABLE [plh].[plh_trz_trazabilidad] ADD [trz_tip_id] TINYINT NULL;
GO

-- 2b. Poblar con el mapeo desde strings existentes
UPDATE [plh].[plh_trz_trazabilidad]
SET trz_tip_id = CASE trz_evento_tipo
    WHEN 'INICIO_FERMENTACION'  THEN 1
    WHEN 'FIN_FERMENTACION'     THEN 2
    WHEN 'INICIO_HORNEADO'      THEN 3
    WHEN 'FIN_HORNEADO'         THEN 4
    WHEN 'RESULTADO_REGISTRADO' THEN 5
    WHEN 'TEMPERATURA'          THEN 6
    WHEN 'OBSERVACION'          THEN 7
    WHEN 'AGREGADO'             THEN 8
    ELSE 7
END
WHERE trz_tip_id IS NULL;
GO

-- 2c. Filas sin match (eventos desconocidos) quedan como OBSERVACION (7)
UPDATE [plh].[plh_trz_trazabilidad]
SET trz_tip_id = 7
WHERE trz_tip_id IS NULL;
GO

-- 2d. Hacer NOT NULL
ALTER TABLE [plh].[plh_trz_trazabilidad]
    ALTER COLUMN [trz_tip_id] TINYINT NOT NULL;
GO

-- 2e. Eliminar columna string (solo si trz_tip_id ya existe y está populada)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND name = 'trz_evento_tipo'
)
BEGIN
    -- Quitar default si existe
    DECLARE @cn NVARCHAR(200);
    SELECT @cn = dc.name
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE c.object_id = OBJECT_ID('plh.plh_trz_trazabilidad') AND c.name = 'trz_evento_tipo';
    IF @cn IS NOT NULL EXEC('ALTER TABLE [plh].[plh_trz_trazabilidad] DROP CONSTRAINT [' + @cn + ']');

    ALTER TABLE [plh].[plh_trz_trazabilidad] DROP COLUMN [trz_evento_tipo];
END;
GO

-- 2f. FK a tipos_evento
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_trz_tip'
)
    ALTER TABLE [plh].[plh_trz_trazabilidad]
        ADD CONSTRAINT FK_trz_tip FOREIGN KEY (trz_tip_id)
            REFERENCES [plh].[plh_tip_tipos_evento] (tip_id);
GO
