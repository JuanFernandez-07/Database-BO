-- =============================================
-- Migration 023: Columnas nuevas en plh_cat_catalogo_productos
-- Idempotente: seguro de re-ejecutar
-- =============================================

USE [sm_backoffice_op];
GO

-- ─── Columnas nuevas en plh_cat_catalogo_productos ───────────────────────────

-- Producto terminado (Mejora 4)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_pro_terminado_codigo')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD [cat_pro_terminado_codigo] NVARCHAR(50) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_pro_terminado_nombre')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD [cat_pro_terminado_nombre] NVARCHAR(255) NULL;
GO

-- Requiere fermentación (Mejora 6)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_requiere_fermentacion')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD [cat_requiere_fermentacion] BIT NOT NULL CONSTRAINT DF_cat_requiere_fermentacion DEFAULT 1;
GO

-- Fracción de bolsa (Mejora 8)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_fraccion_bolsa')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD [cat_fraccion_bolsa] DECIMAL(4,2) NOT NULL CONSTRAINT DF_cat_fraccion_bolsa DEFAULT 1.00;
GO

-- Producto sustituto para proyección (productos de temporada sin historial)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('plh.plh_cat_catalogo_productos') AND name = 'cat_pro_sustituto_codigo')
    ALTER TABLE [plh].[plh_cat_catalogo_productos] ADD [cat_pro_sustituto_codigo] NVARCHAR(50) NULL;
GO
