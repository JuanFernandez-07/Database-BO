-- =============================================
-- Script: 013_Fix_CostoComida_Desincronizado
-- Modulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripcion: Recalcula pld_pct/pld_monto de los rubros con desglose
--              (aplica_menu=1 - hoy solo Costo de Comida) en
--              pyl.prg_pld_plan_detalle, sumando el % real de sus lineas en
--              pyl.prg_pdm_plan_detalle_menu - exactamente lo mismo que hace
--              ActualizarLineaDeMenuAsync (ActualizarLineaPlanCommandHandler.cs)
--              cada vez que se guarda una linea del desglose desde la
--              pantalla. La pantalla SIEMPRE recalcula esta suma en vivo
--              (RubroValorResolver.ResolverPorcentaje), nunca lee pld_pct/
--              pld_monto del padre directamente - por eso esa fila puede
--              quedar desincronizada (ej. si el desglose se toco sin pasar
--              por un guardado normal) sin que se note en pantalla, pero si
--              se nota en consultas SQL directas contra prg_pld_plan_detalle.
--
--              pld_monto = pld_pct/100 * venta de esa tienda/anio/mes. La
--              venta se resuelve con el MISMO criterio de fecha que
--              PlVentaExternaRepository.GetVentaAnioAsync: real
--              (sm_pos.dbo.Venta_Mes) para meses ya cerrados, proyeccion
--              (pyl.pve_proyeccion_venta) para el mes en curso o futuros -
--              necesario porque este fix cubre CUALQUIER tienda/anio/mes, no
--              solo un caso puntual.
--
--              Primero corre el SELECT de preview (paso 1) para revisar el
--              alcance antes de aplicar el UPDATE (paso 2).
-- Base: sm_backoffice
-- Fecha: 2026-09-30
-- =============================================

USE [sm_backoffice];
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── Paso 1: Preview - revisar ANTES de aplicar el UPDATE ────────────────────

;WITH DesgloseSumado AS (
    SELECT
        pdm_id_negocio AS IdNegocio, pdm_id_reporte AS IdReporte,
        pdm_tienda_codigo AS TiendaCodigo, pdm_anio AS Anio, pdm_mes AS Mes,
        pdm_id_rubro AS IdRubro,
        SUM(pdm_pct) AS PctTotal
    FROM [pyl].[prg_pdm_plan_detalle_menu]
    WHERE pdm_id_negocio = @idNegocio AND pdm_id_reporte = @idReporte
    GROUP BY pdm_id_negocio, pdm_id_reporte, pdm_tienda_codigo, pdm_anio, pdm_mes, pdm_id_rubro
),
VentaReal AS (
    SELECT tie_codigo_neg AS IdNegocio, tie_codigo_bo AS TiendaCodigo, [YEAR] AS Anio, [MONTH] AS Mes, SUM([Amount]) AS Monto
    FROM [sm_pos].[dbo].[Venta_Mes]
    WHERE tie_codigo_neg = @idNegocio
    GROUP BY tie_codigo_neg, tie_codigo_bo, [YEAR], [MONTH]
),
VentaProyectada AS (
    SELECT pv.pve_codigo_neg AS IdNegocio, pv.pve_codigo_tie AS TiendaCodigo, pv.pve_anio_proyectar AS Anio, m.Mes, m.Monto
    FROM [pyl].[pve_proyeccion_venta] AS pv
    CROSS APPLY (VALUES
        (1, pv.pve_enero_proyecccion),      (2, pv.pve_febrero_proyecccion),
        (3, pv.pve_marzo_proyecccion),      (4, pv.pve_abril_proyecccion),
        (5, pv.pve_mayo_proyecccion),       (6, pv.pve_junio_proyecccion),
        (7, pv.pve_julio_proyecccion),      (8, pv.pve_agosto_proyecccion),
        (9, pv.pve_septiembre_proyecccion), (10, pv.pve_octubre_proyecccion),
        (11, pv.pve_noviembre_proyecccion), (12, pv.pve_diciembre_proyecccion)
    ) AS m(Mes, Monto)
    WHERE pv.pve_codigo_neg = @idNegocio
),
VentaResuelta AS (
    -- Mismo criterio de fecha que GetVentaAnioAsync: real para meses ya
    -- cerrados, proyeccion para el mes en curso o futuros.
    SELECT
        d.IdNegocio, d.TiendaCodigo, d.Anio, d.Mes,
        CASE
            WHEN d.Anio < YEAR(GETDATE()) OR (d.Anio = YEAR(GETDATE()) AND d.Mes < MONTH(GETDATE()))
                THEN ISNULL(vr.Monto, 0)
            ELSE ISNULL(vp.Monto, 0)
        END AS VentaMonto
    FROM (SELECT DISTINCT IdNegocio, TiendaCodigo, Anio, Mes FROM DesgloseSumado) AS d
    LEFT JOIN VentaReal AS vr ON vr.IdNegocio = d.IdNegocio AND vr.TiendaCodigo = d.TiendaCodigo AND vr.Anio = d.Anio AND vr.Mes = d.Mes
    LEFT JOIN VentaProyectada AS vp ON vp.IdNegocio = d.IdNegocio AND vp.TiendaCodigo = d.TiendaCodigo AND vp.Anio = d.Anio AND vp.Mes = d.Mes
)
SELECT
    pld.pld_tienda_codigo, pld.pld_anio, pld.pld_mes, pld.pld_id_rubro,
    pld.pld_pct AS pct_actual_en_bd, ds.PctTotal AS pct_correcto,
    pld.pld_monto AS monto_actual_en_bd,
    CASE WHEN vr.VentaMonto = 0 THEN 0 ELSE ds.PctTotal / 100.0 * vr.VentaMonto END AS monto_correcto,
    vr.VentaMonto AS venta_usada
FROM [pyl].[prg_pld_plan_detalle] AS pld
INNER JOIN DesgloseSumado AS ds
    ON pld.pld_id_negocio = ds.IdNegocio AND pld.pld_id_reporte = ds.IdReporte
   AND pld.pld_tienda_codigo = ds.TiendaCodigo AND pld.pld_anio = ds.Anio
   AND pld.pld_mes = ds.Mes AND pld.pld_id_rubro = ds.IdRubro
INNER JOIN VentaResuelta AS vr
    ON vr.IdNegocio = ds.IdNegocio AND vr.TiendaCodigo = ds.TiendaCodigo AND vr.Anio = ds.Anio AND vr.Mes = ds.Mes
WHERE pld.pld_pct <> ds.PctTotal
   OR pld.pld_monto <> CASE WHEN vr.VentaMonto = 0 THEN 0 ELSE ds.PctTotal / 100.0 * vr.VentaMonto END
ORDER BY pld.pld_tienda_codigo, pld.pld_anio, pld.pld_mes;
GO

-- ─── Paso 2: UPDATE - correr solo despues de revisar el preview de arriba ────
-- (Comentado a proposito: descomentar para aplicar.)

/*
;WITH DesgloseSumado AS (
    SELECT
        pdm_id_negocio AS IdNegocio, pdm_id_reporte AS IdReporte,
        pdm_tienda_codigo AS TiendaCodigo, pdm_anio AS Anio, pdm_mes AS Mes,
        pdm_id_rubro AS IdRubro,
        SUM(pdm_pct) AS PctTotal
    FROM [pyl].[prg_pdm_plan_detalle_menu]
    WHERE pdm_id_negocio = @idNegocio AND pdm_id_reporte = @idReporte
    GROUP BY pdm_id_negocio, pdm_id_reporte, pdm_tienda_codigo, pdm_anio, pdm_mes, pdm_id_rubro
),
VentaReal AS (
    SELECT tie_codigo_neg AS IdNegocio, tie_codigo_bo AS TiendaCodigo, [YEAR] AS Anio, [MONTH] AS Mes, SUM([Amount]) AS Monto
    FROM [sm_pos].[dbo].[Venta_Mes]
    WHERE tie_codigo_neg = @idNegocio
    GROUP BY tie_codigo_neg, tie_codigo_bo, [YEAR], [MONTH]
),
VentaProyectada AS (
    SELECT pv.pve_codigo_neg AS IdNegocio, pv.pve_codigo_tie AS TiendaCodigo, pv.pve_anio_proyectar AS Anio, m.Mes, m.Monto
    FROM [pyl].[pve_proyeccion_venta] AS pv
    CROSS APPLY (VALUES
        (1, pv.pve_enero_proyecccion),      (2, pv.pve_febrero_proyecccion),
        (3, pv.pve_marzo_proyecccion),      (4, pv.pve_abril_proyecccion),
        (5, pv.pve_mayo_proyecccion),       (6, pv.pve_junio_proyecccion),
        (7, pv.pve_julio_proyecccion),      (8, pv.pve_agosto_proyecccion),
        (9, pv.pve_septiembre_proyecccion), (10, pv.pve_octubre_proyecccion),
        (11, pv.pve_noviembre_proyecccion), (12, pv.pve_diciembre_proyecccion)
    ) AS m(Mes, Monto)
    WHERE pv.pve_codigo_neg = @idNegocio
),
VentaResuelta AS (
    SELECT
        d.IdNegocio, d.TiendaCodigo, d.Anio, d.Mes,
        CASE
            WHEN d.Anio < YEAR(GETDATE()) OR (d.Anio = YEAR(GETDATE()) AND d.Mes < MONTH(GETDATE()))
                THEN ISNULL(vr.Monto, 0)
            ELSE ISNULL(vp.Monto, 0)
        END AS VentaMonto
    FROM (SELECT DISTINCT IdNegocio, TiendaCodigo, Anio, Mes FROM DesgloseSumado) AS d
    LEFT JOIN VentaReal AS vr ON vr.IdNegocio = d.IdNegocio AND vr.TiendaCodigo = d.TiendaCodigo AND vr.Anio = d.Anio AND vr.Mes = d.Mes
    LEFT JOIN VentaProyectada AS vp ON vp.IdNegocio = d.IdNegocio AND vp.TiendaCodigo = d.TiendaCodigo AND vp.Anio = d.Anio AND vp.Mes = d.Mes
)
UPDATE pld
SET pld.pld_pct = ds.PctTotal,
    pld.pld_monto = CASE WHEN vr.VentaMonto = 0 THEN 0 ELSE ds.PctTotal / 100.0 * vr.VentaMonto END
FROM [pyl].[prg_pld_plan_detalle] AS pld
INNER JOIN DesgloseSumado AS ds
    ON pld.pld_id_negocio = ds.IdNegocio AND pld.pld_id_reporte = ds.IdReporte
   AND pld.pld_tienda_codigo = ds.TiendaCodigo AND pld.pld_anio = ds.Anio
   AND pld.pld_mes = ds.Mes AND pld.pld_id_rubro = ds.IdRubro
INNER JOIN VentaResuelta AS vr
    ON vr.IdNegocio = ds.IdNegocio AND vr.TiendaCodigo = ds.TiendaCodigo AND vr.Anio = ds.Anio AND vr.Mes = ds.Mes
WHERE pld.pld_pct <> ds.PctTotal
   OR pld.pld_monto <> CASE WHEN vr.VentaMonto = 0 THEN 0 ELSE ds.PctTotal / 100.0 * vr.VentaMonto END;
*/
GO
