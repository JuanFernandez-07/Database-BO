-- =============================================
-- RESPALDO — versión ORIGINAL de fn_plh_VentaCongeladoPorDia (antes del cambio de sargabilidad).
-- Usar SOLO para la comparación de validación (paso 1 del script de comparación).
-- NO desplegar a producción; la versión a desplegar es StoredProceduresFinal/09_Funciones.sql.
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER FUNCTION [plh].[fn_plh_VentaCongeladoPorDia]
(
    @TiendaCodigo INT,
    @CodigoNeg    NVARCHAR(10),
    @Fecha        DATE
)
RETURNS TABLE
AS RETURN
(
    WITH DataArea AS (
        SELECT n.neg_referencia1 AS data_area_id
        FROM plh.Vw_plh_neg_Negocios n
        WHERE CAST(n.neg_codigo AS NVARCHAR(20)) = @CodigoNeg
    )
    SELECT
        cat.cat_pro_codigo                                      AS CodigoCongelado,
        ROUND(ISNULL(SUM(
            g.Cantidad
            * rd.Cantidad_Item
            * ISNULL(
                CASE WHEN rd.Unidad_Medida LIKE '%[0-9]U'
                     THEN TRY_CAST(
                            SUBSTRING(
                                rd.Unidad_Medida,
                                PATINDEX('%[0-9]%', rd.Unidad_Medida),
                                LEN(rd.Unidad_Medida) - PATINDEX('%[0-9]%', rd.Unidad_Medida)
                            ) AS INT)
                     ELSE 1
                END, 1)
        ), 0), 2)                                               AS VentaTerminado
    FROM plh.plh_cat_catalogo_productos cat
    INNER JOIN plh.Receta_detalle rd
        ON  rd.Codigo_Item = cat.cat_pro_codigo
        AND rd.Codigo_Item <> CAST(rd.Id_Receta AS VARCHAR(50))
        AND rd.DataAreaId  = (SELECT data_area_id FROM DataArea)
        AND rd.Modificador <> 1
    LEFT JOIN plh.Vw_Vista_Consumo g
        ON  CAST(g.ITEM AS VARCHAR(50)) = CAST(rd.Id_Receta AS VARCHAR(50))
        AND g.LC_UNIT   = @TiendaCodigo
        AND g.LC_DOB    = @Fecha
        AND g.Cantidad  > 0
    WHERE cat.cat_codigo_neg    = @CodigoNeg
      AND cat.cat_tienda_codigo IN (0, @TiendaCodigo)
      AND cat.cat_activo        = 1
    GROUP BY cat.cat_pro_codigo
);
GO
