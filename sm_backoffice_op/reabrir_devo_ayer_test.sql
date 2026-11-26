-- =============================================
-- Solo para pruebas en dev: reabre, por cada tienda/negocio, la fecha más cercana a
-- hoy (hacia atrás) que tenga registros de DEVO (Cocina y Panadería/General, sin
-- tocar repostería) — no asume "ayer" porque en dev los datos están dispersos y no
-- todas las tiendas tienen registro el mismo día. Así se puede validar el gate de
-- cierre secuencial nuevo sin esperar a que haya datos de ayer.
-- =============================================

USE [sm_backoffice_op];
GO

-- Previsualización: para cada tienda, cuál es su fecha más cercana a hoy (antes de
-- hoy) con registros, y cuántas filas de esa fecha quedarían abiertas.
;WITH FechaMasCercana AS (
    SELECT
        d.dev_codigo_neg,
        d.dev_tienda_codigo,
        MAX(d.dev_fecha_registro) AS fecha_objetivo
    FROM plh.plh_dev_devoluciones d
    OUTER APPLY (
        SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
        FROM plh.plh_cat_catalogo_productos c
        WHERE c.cat_pro_codigo    = d.dev_pro_codigo
          AND c.cat_codigo_neg    = d.dev_codigo_neg
          AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
        ORDER BY c.cat_tienda_codigo DESC
    ) tipo
    WHERE d.dev_fecha_registro < CAST(GETDATE() AS DATE)
      AND (d.dev_origen_cocina = 1 OR ISNULL(tipo.EsReposteria, 0) = 0)
    GROUP BY d.dev_codigo_neg, d.dev_tienda_codigo
)
SELECT
    f.dev_codigo_neg,
    f.dev_tienda_codigo,
    f.fecha_objetivo,
    COUNT(*)                  AS filas_a_reabrir,
    SUM(CASE WHEN d.dev_origen_cocina = 1 THEN 1 ELSE 0 END) AS de_cocina,
    SUM(CASE WHEN d.dev_origen_cocina = 0 THEN 1 ELSE 0 END) AS de_panaderia
FROM FechaMasCercana f
JOIN plh.plh_dev_devoluciones d
    ON  d.dev_codigo_neg     = f.dev_codigo_neg
    AND d.dev_tienda_codigo  = f.dev_tienda_codigo
    AND d.dev_fecha_registro = f.fecha_objetivo
GROUP BY f.dev_codigo_neg, f.dev_tienda_codigo, f.fecha_objetivo
ORDER BY f.dev_codigo_neg, f.dev_tienda_codigo;
GO

-- Reapertura real — descomenta y corre después de revisar la previsualización.
/*
;WITH FechaMasCercana AS (
    SELECT
        d.dev_codigo_neg,
        d.dev_tienda_codigo,
        MAX(d.dev_fecha_registro) AS fecha_objetivo
    FROM plh.plh_dev_devoluciones d
    OUTER APPLY (
        SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
        FROM plh.plh_cat_catalogo_productos c
        WHERE c.cat_pro_codigo    = d.dev_pro_codigo
          AND c.cat_codigo_neg    = d.dev_codigo_neg
          AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
        ORDER BY c.cat_tienda_codigo DESC
    ) tipo
    WHERE d.dev_fecha_registro < CAST(GETDATE() AS DATE)
      AND (d.dev_origen_cocina = 1 OR ISNULL(tipo.EsReposteria, 0) = 0)
    GROUP BY d.dev_codigo_neg, d.dev_tienda_codigo
)
UPDATE d
SET d.dev_dia_cerrado = 0
FROM plh.plh_dev_devoluciones d
JOIN FechaMasCercana f
    ON  d.dev_codigo_neg     = f.dev_codigo_neg
    AND d.dev_tienda_codigo  = f.dev_tienda_codigo
    AND d.dev_fecha_registro = f.fecha_objetivo;

SELECT @@ROWCOUNT AS filas_reabiertas;
*/
GO
