-- =============================================
-- Migration 004: CR-20260410-02
-- Agrega campos faltantes a plh_cat_catalogo_productos
--   cat_aplica_pedido_cocina: si el producto aplica para pedido de cocina
--   cat_estacional: si el producto es de temporada
-- =============================================

ALTER TABLE [plh].[plh_cat_catalogo_productos]
    ADD [cat_aplica_pedido_cocina] BIT NOT NULL CONSTRAINT DF_cat_aplica_pedido_cocina DEFAULT 0,
        [cat_estacional]           BIT NOT NULL CONSTRAINT DF_cat_estacional           DEFAULT 0;
GO
