-- ─── Vw_plh_neg_Negocios ────────────────────────────────────────────────────
-- Vista sustituta de plh.plh_neg_negocios.
-- Lee directamente desde la fuente de verdad en sm_backoffice.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR ALTER VIEW [plh].[Vw_plh_neg_Negocios]
AS
SELECT
    [neg_codigo],
    [neg_codigo_pai],
    [neg_nombre],
    [neg_alias],
    [neg_alias_erp],
    [neg_referencia1],
    [neg_moneda]
FROM [sm_backoffice].[pri].[est_neg_negocio];
GO
