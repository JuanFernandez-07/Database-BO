-- =============================================
-- Script: 012_Backfill_FilaVenta_2027
-- Modulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripcion: Inserta la fila de Venta (rubro tipo Venta, id_rubro=1) en
--              pyl.prg_pld_plan_detalle para negocio=1/reporte=1/anio=2027,
--              para toda combinacion tienda/mes que YA tenga al menos una
--              linea capturada ese mes pero que todavia no tenga su fila de
--              Venta (auto-vivify normalmente la crea el codigo al guardar,
--              ver ActualizarLineaPlanCommandHandler.cs - este script cubre
--              retroactivamente lo que ya se habia guardado ANTES de ese
--              cambio y que nadie ha vuelto a tocar desde entonces).
--              No crea nada para tienda/mes sin ningun dato capturado (no
--              tendria encabezado ni sentido crear la Venta suelta ahi).
--
--              Fuente del monto: 2027 es completamente futuro respecto a hoy
--              (2026-09-29), asi que TODO el anio usa la proyeccion
--              (pyl.pve_proyeccion_venta) - mismo criterio de fecha que
--              PlVentaExternaRepository.GetVentaAnioAsync (ningun mes de 2027
--              calificaria como "real" via sm_pos.dbo.Venta_Mes todavia). Si
--              se necesitara correr esto para un anio que ya tiene meses
--              cerrados, habria que mezclar ambas fuentes como hace ese mismo
--              repositorio.
--
--              pld_pct=100, pld_base_monto=0, pld_orden=orden de Venta en el
--              catalogo - mismos valores que pone el codigo nuevo al guardar.
--              Idempotente: solo inserta donde todavia no existe esa fila.
-- Base: sm_backoffice
-- Fecha: 2026-09-29
-- =============================================

USE [sm_backoffice];
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;
DECLARE @anio INT = 2027;

DECLARE @idRubroVenta INT = (
    SELECT rub_id_rubro FROM [pyl].[prg_rub_rubro]
    WHERE rub_id_negocio = @idNegocio AND rub_id_reporte = @idReporte AND rub_tipo_dato = 1
);
DECLARE @ordenVenta INT = (
    SELECT rub_orden FROM [pyl].[prg_rub_rubro]
    WHERE rub_id_negocio = @idNegocio AND rub_id_reporte = @idReporte AND rub_id_rubro = @idRubroVenta
);

;WITH MesesConDatos AS (
    -- Cada combinacion (tienda, mes) que ya tiene al menos una linea
    -- capturada en @anio - ahi es donde hace falta la fila de Venta.
    SELECT DISTINCT pld_tienda_codigo AS TiendaCodigo, pld_mes AS Mes
    FROM [pyl].[prg_pld_plan_detalle]
    WHERE pld_id_negocio = @idNegocio AND pld_id_reporte = @idReporte AND pld_anio = @anio
),
VentaProyectada AS (
    SELECT pv.pve_codigo_tie AS TiendaCodigo, m.Mes, m.Monto
    FROM [pyl].[pve_proyeccion_venta] AS pv
    CROSS APPLY (VALUES
        (1, pv.pve_enero_proyecccion),    (2, pv.pve_febrero_proyecccion),
        (3, pv.pve_marzo_proyecccion),    (4, pv.pve_abril_proyecccion),
        (5, pv.pve_mayo_proyecccion),     (6, pv.pve_junio_proyecccion),
        (7, pv.pve_julio_proyecccion),    (8, pv.pve_agosto_proyecccion),
        (9, pv.pve_septiembre_proyecccion), (10, pv.pve_octubre_proyecccion),
        (11, pv.pve_noviembre_proyecccion), (12, pv.pve_diciembre_proyecccion)
    ) AS m(Mes, Monto)
    WHERE pv.pve_codigo_neg = @idNegocio AND pv.pve_anio_proyectar = @anio
)
INSERT INTO [pyl].[prg_pld_plan_detalle] (
    pld_id_negocio, pld_id_reporte, pld_tienda_codigo, pld_anio, pld_mes, pld_id_rubro,
    pld_monto, pld_pct, pld_pct_ly, pld_pct_diferencia, pld_base_monto, pld_base_pct, pld_orden
)
SELECT
    @idNegocio, @idReporte, md.TiendaCodigo, @anio, md.Mes, @idRubroVenta,
    ISNULL(vp.Monto, 0), 100.0000, 0, 0, 0, 0, @ordenVenta
FROM MesesConDatos AS md
LEFT JOIN VentaProyectada AS vp
    ON vp.TiendaCodigo = md.TiendaCodigo AND vp.Mes = md.Mes
WHERE NOT EXISTS (
    SELECT 1 FROM [pyl].[prg_pld_plan_detalle] AS existente
    WHERE existente.pld_id_negocio = @idNegocio AND existente.pld_id_reporte = @idReporte
      AND existente.pld_tienda_codigo = md.TiendaCodigo AND existente.pld_anio = @anio
      AND existente.pld_mes = md.Mes AND existente.pld_id_rubro = @idRubroVenta
);
GO
