-- =============================================
-- Migración 020: Tabla plh.plh_neg_negocios en sm_backoffice_op
--
-- Propósito: Copia local de pri.est_neg_negocio (sm_backoffice) para evitar
--            cross-DB access desde el usuario de la aplicación (Plh_app_user).
--            Los SPs del módulo PLH usan esta tabla para mapear:
--                neg_alias       → alias Aloha (ej. 'SMGT') → Vw_Vista_Venta_proyectada
--                neg_referencia1 → DataAreaId (ej. 'PAN')   → Receta_detalle
-- =============================================

USE [sm_backoffice_op];
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t
    INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name = 'plh' AND t.name = 'plh_neg_negocios'
)
BEGIN
    CREATE TABLE [plh].[plh_neg_negocios] (
        [neg_codigo]      INT            NOT NULL,
        [neg_codigo_pai]  INT            NULL,
        [neg_nombre]      VARCHAR(50)    NULL,
        [neg_alias]       NVARCHAR(10)   NULL,
        [neg_alias_erp]   NVARCHAR(20)   NULL,
        [neg_referencia1] NVARCHAR(100)  NULL,
        [neg_moneda]      NVARCHAR(3)    NULL,
        CONSTRAINT PK_plh_neg_negocios PRIMARY KEY CLUSTERED ([neg_codigo] ASC)
    );
END
GO

-- ─── Poblar con los datos del negocio ─────────────────────────────────────────
INSERT INTO [plh].[plh_neg_negocios]
    (neg_codigo, neg_codigo_pai, neg_nombre, neg_alias, neg_alias_erp, neg_referencia1, neg_moneda)
SELECT v.neg_codigo, v.neg_codigo_pai, v.neg_nombre, v.neg_alias, v.neg_alias_erp, v.neg_referencia1, v.neg_moneda
FROM (VALUES
    (1, 1, 'San Martín Guatemala',         'SMGT',  'LPN',    'PAN', 'GTQ'),
    (2, 2, 'San Martín El Salvador',        'SMSV',  'COR',    'COR', 'USD'),
    (3, 3, 'San Martín USA',                'SMUS',  'LPNUSA', 'USA', 'USD'),
    (4, 1, 'Cielito Lindo Guatemala',       'CLGT',  'LPN',    'CL',  'GTQ'),
    (5, 1, 'Cielito Lindo Grill Guatemala', 'GRLGT', 'LPN',    'GRL', 'GTQ')
) AS v(neg_codigo, neg_codigo_pai, neg_nombre, neg_alias, neg_alias_erp, neg_referencia1, neg_moneda)
WHERE NOT EXISTS (
    SELECT 1 FROM [plh].[plh_neg_negocios] x WHERE x.neg_codigo = v.neg_codigo
);
GO