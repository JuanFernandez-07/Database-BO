-- Notas importantes para agregar correctamente:
--
--   1) Sugerido, Planificado y Aceptado SÍ son por horneada — para el total
--      del producto/día, hacer SUM() agrupando por producto/tienda/fecha.
--
--   2) VentaHoy es un valor por PRODUCTO/DÍA (no por horneada) — viene
--      repetido igual en cada horneada de ese producto. Para el total NO
--      sumar entre horneadas: usar MAX() (o AVG(), da lo mismo) agrupando
--      por producto/tienda/fecha.
--
--   3) DevueltoPanaderia también es por PRODUCTO/DÍA (no siempre se puede
--      asociar a una horneada específica), y viene repetido igual en cada
--      horneada de ese producto — mismo criterio que VentaHoy: usar MAX(),
--      NUNCA SUM() entre horneadas, o se multiplica el total.
--
--   4) InventarioFinal (Cantidad Final de Control de Repostería) SÍ es por
--      horneada — para el FIFO se necesitan DOS cosas distintas:
--        a) InventarioFinalTotal = SUM(InventarioFinal) de TODAS las
--           horneadas del producto ese día.
--        b) InvFinalUltimaHorneada = el InventarioFinal de la horneada
--           "más reciente" del día. Regla para identificarla (igual que en
--           pantalla): es la de mayor HorneadaNumero con EsProductosDirectos
--           = 0 (horneada normal); PERO si existe una horneada de Productos
--           Directos (EsProductosDirectos = 1) con HorneadaNumero MAYOR que
--           esa, hay que sumarle también su InventarioFinal (ocurre después
--           en el día). Esta "última horneada" es la misma para todos los
--           productos de una tienda/fecha, no varía por producto.
--
--   5) InventarioFinal y el FIFO Score solo son significativos cuando
--      AplicaControlReposteria = 1 — para el resto de productos no hay
--      control de inventario final, ignorar esas filas para ese cálculo.
-- =============================================

USE [DWH_Views];
GO

CREATE OR ALTER VIEW [dbo].[DWH_Vw_KPI_PlanHornos]
AS
WITH PlanBase AS (
    SELECT
        pla.pla_codigo_neg                                                 AS CodigoNeg,
        pla.pla_tienda_codigo                                              AS TiendaCodigo,
        pla.pla_fecha                                                      AS Fecha,
        pld.pld_pro_codigo                                                 AS ProductoCodigo,
        ISNULL(cat.cat_pro_nombre, pld.pld_pro_codigo)                     AS ProductoNombre,
        ph.plh_hor_numero_secuencia                                        AS HorneadaNumero,
        h.hor_hora_inicio                                                  AS HorneadaHoraInicio,
        h.hor_solo_productos_directos                                      AS EsProductosDirectos,
        ph.plh_proyeccion                                                  AS Sugerido,
        ph.plh_cantidad_hornear                                            AS Planificado,
        pld.pld_venta_hoy                                                  AS VentaHoy,
        fct.AplicaControlReposteria                                        AS AplicaControlReposteria,
        ISNULL(fct.FactorConversion, 1)                                    AS FactorConversion
    FROM [sm_backoffice_op].[plh].[plh_pla_planes] pla
    INNER JOIN [sm_backoffice_op].[plh].[plh_pld_plan_detalle]  pld
        ON  pld.pld_codigo_neg    = pla.pla_codigo_neg
        AND pld.pld_tienda_codigo = pla.pla_tienda_codigo
        AND pld.pld_fecha         = pla.pla_fecha
    INNER JOIN [sm_backoffice_op].[plh].[plh_plh_plan_horneada] ph
        ON  ph.plh_codigo_neg    = pld.pld_codigo_neg
        AND ph.plh_tienda_codigo = pld.pld_tienda_codigo
        AND ph.plh_fecha         = pld.pld_fecha
        AND ph.plh_pro_codigo    = pld.pld_pro_codigo
    INNER JOIN [sm_backoffice_op].[plh].[plh_hor_horneadas] h
        ON  h.hor_codigo_neg       = ph.plh_codigo_neg
        AND h.hor_tienda_codigo    = ph.plh_tienda_codigo
        AND h.hor_numero_secuencia = ph.plh_hor_numero_secuencia
    LEFT JOIN [sm_backoffice_op].[plh].[plh_cat_catalogo_productos] cat
        ON  cat.cat_pro_codigo    = pld.pld_pro_codigo
        AND cat.cat_codigo_neg    = pla.pla_codigo_neg
        AND cat.cat_tienda_codigo IN (0, pla.pla_tienda_codigo)
    OUTER APPLY (
        SELECT TOP 1
            ISNULL(c2.cat_factor_conversion, 1)                      AS FactorConversion,
            CAST(ISNULL(c2.cat_aplica_control_reposteria, 0) AS INT) AS AplicaControlReposteria
        FROM [sm_backoffice_op].[plh].[plh_cat_catalogo_productos] c2
        WHERE c2.cat_pro_codigo    = pld.pld_pro_codigo
          AND c2.cat_codigo_neg    = pla.pla_codigo_neg
          AND c2.cat_tienda_codigo IN (0, pla.pla_tienda_codigo)
        ORDER BY c2.cat_tienda_codigo DESC
    ) fct
),
Aceptado AS (
    -- Horneado total aceptado (Recepción de Horneado), por producto x horneada.
    SELECT
        enc.prh_codigo_neg           AS CodigoNeg,
        enc.prh_tienda_codigo        AS TiendaCodigo,
        enc.prh_fecha                AS Fecha,
        enc.prh_pro_codigo           AS ProductoCodigo,
        enc.prh_hor_numero_secuencia AS HorneadaNumero,
        ISNULL(det.prh_cantidad_aceptada, 0) AS Aceptado
    FROM [sm_backoffice_op].[plh].[plh_prh_proceso_horneado_encabezado] enc
    LEFT JOIN [sm_backoffice_op].[plh].[plh_prh_proceso_horneado_detalle] det
        ON  det.prh_codigo_neg           = enc.prh_codigo_neg
        AND det.prh_tienda_codigo        = enc.prh_tienda_codigo
        AND det.prh_fecha                = enc.prh_fecha
        AND det.prh_pro_codigo           = enc.prh_pro_codigo
        AND det.prh_hor_numero_secuencia = enc.prh_hor_numero_secuencia
),
InvFinal AS (
    -- Cantidad Final (Control de Repostería), por producto x horneada.
    -- Excluye traslados (no tienen horneada propia ni forman parte de esta pantalla).
    SELECT
        rot_codigo_neg           AS CodigoNeg,
        rot_tienda_codigo        AS TiendaCodigo,
        rot_fecha                AS Fecha,
        rot_pro_codigo           AS ProductoCodigo,
        rot_hor_numero_secuencia AS HorneadaNumero,
        rot_cantidad_final       AS InventarioFinal
    FROM [sm_backoffice_op].[plh].[plh_rot_rotacion]
    WHERE rot_es_transferencia = 0
),
DevueltoPanaderia AS (
    -- Total de devolución por producto/día (en producción, 100% panadería
    -- hoy — ver nota de alcance arriba). Es por PRODUCTO/DÍA, no por
    -- horneada — ver nota 3 arriba antes de agregar.
    SELECT
        dev_codigo_neg     AS CodigoNeg,
        dev_tienda_codigo  AS TiendaCodigo,
        dev_fecha_registro AS Fecha,
        dev_pro_codigo     AS ProductoCodigo,
        SUM(dev_cantidad)  AS Devuelto
    FROM [sm_backoffice_op].[plh].[plh_dev_devoluciones]
    GROUP BY dev_codigo_neg, dev_tienda_codigo, dev_fecha_registro, dev_pro_codigo
)
SELECT
    pb.CodigoNeg,
    pb.TiendaCodigo,
    pb.Fecha,
    pb.ProductoCodigo,
    pb.ProductoNombre,
    pb.HorneadaNumero,
    pb.HorneadaHoraInicio,
    pb.EsProductosDirectos,
    pb.AplicaControlReposteria,
    pb.FactorConversion,
    pb.Sugerido,
    pb.Planificado,
    pb.VentaHoy,
    ISNULL(a.Aceptado, 0)   AS Aceptado,
    inv.InventarioFinal,
    ISNULL(d.Devuelto, 0)   AS DevueltoPanaderia
FROM PlanBase pb
LEFT JOIN Aceptado a
    ON  a.CodigoNeg = pb.CodigoNeg AND a.TiendaCodigo = pb.TiendaCodigo AND a.Fecha = pb.Fecha
    AND a.ProductoCodigo = pb.ProductoCodigo AND a.HorneadaNumero = pb.HorneadaNumero
LEFT JOIN InvFinal inv
    ON  inv.CodigoNeg = pb.CodigoNeg AND inv.TiendaCodigo = pb.TiendaCodigo AND inv.Fecha = pb.Fecha
    AND inv.ProductoCodigo = pb.ProductoCodigo AND inv.HorneadaNumero = pb.HorneadaNumero
LEFT JOIN DevueltoPanaderia d
    ON  d.CodigoNeg = pb.CodigoNeg AND d.TiendaCodigo = pb.TiendaCodigo AND d.Fecha = pb.Fecha
    AND d.ProductoCodigo = pb.ProductoCodigo;
GO

