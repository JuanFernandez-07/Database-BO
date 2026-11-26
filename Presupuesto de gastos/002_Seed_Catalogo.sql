-- =============================================
-- Script: 002_Seed_Catalogo
-- Módulo: Presupuesto de Gastos (P&L Tiendas)
-- Descripción: Siembra el catálogo (Reporte, Rubro Grupo, Rubros, Rubro Menú,
--              Rubro Cálculo) para idNegocio=1 — compartido por todas las
--              tiendas de ese negocio. El Plan Encabezado/Plan Detalle de cada
--              tienda se crea solo (auto-vivify) la primera vez que esa tienda
--              guarda una línea desde la pantalla — no se siembra aquí.
--              Idempotente: seguro de re-ejecutar.
-- Base: sm_backoffice
-- Fecha: 2026-09-02
-- =============================================

USE [sm_backoffice];
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── 1. Reporte ──────────────────────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM [pyl].[prg_rep_reporte] WHERE rep_id_negocio = @idNegocio AND rep_id_reporte = @idReporte)
BEGIN
    INSERT INTO [pyl].[prg_rep_reporte] (rep_id_negocio, rep_id_reporte, rep_nombre, rep_id_estado)
    VALUES (@idNegocio, @idReporte, N'Presupuesto de Gastos', 1);
END
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── 2. Rubro Grupo ──────────────────────────────────────────────────────────
-- Grupos 3 y 5 llevan un solo rubro (cierre de sección) — el frontend no les
-- pinta encabezado propio, pero igual necesitan nombre en la tabla.

MERGE [pyl].[prg_rgp_rubro_grupo] AS destino
USING (VALUES
    (1, N'Venta'),
    (2, N'Costo de Ventas'),
    (3, N'Utilidad Bruta'),
    (4, N'Gastos Controlables'),
    (5, N'Utilidad Después de Controlables')
) AS origen (id_grupo, nombre)
ON destino.rgp_id_negocio = @idNegocio AND destino.rgp_id_reporte = @idReporte AND destino.rgp_id_grupo = origen.id_grupo
WHEN MATCHED THEN
    UPDATE SET rgp_nombre = origen.nombre
WHEN NOT MATCHED THEN
    INSERT (rgp_id_negocio, rgp_id_reporte, rgp_id_grupo, rgp_nombre, rgp_id_estado)
    VALUES (@idNegocio, @idReporte, origen.id_grupo, origen.nombre, 1);
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── 3. Rubros ───────────────────────────────────────────────────────────────
-- tipo_dato: 1-Venta, 2-Calculo, 3-Porcentaje, 4-Monto.
-- Confirmado contra el histórico real (pyl.vta_rme_reporte_mes.rme_tipo_dato,
-- que coincide 1:1 por id_rubro con este catálogo): si en el histórico el
-- rubro se registra en monto, aquí va Monto(4); si se registra en %, va
-- Porcentaje(3). De los 13 Controlables, solo 2 son Porcentaje (Gastos
-- Mercadeo) — Costo de Comida/Empaque/Flete (grupo Costo de Venta) también son
-- Porcentaje — el resto, incluyendo Empleados Planillas y Motivación y
-- Reconocimiento, son Monto. Confirmado con el usuario 2026-09-23 (corrige la
-- nota anterior, que tenía Empleados Planillas/Motivación como Porcentaje).
-- El presupuesto de gastos solo llega hasta "Utilidad Después de
-- Controlables" (id 21) — No Controlables/UO/EBITDA quedan fuera por ahora.

MERGE [pyl].[prg_rub_rubro] AS destino
USING (VALUES
    -- id_rubro, nombre, tipo_dato, aplica_menu, id_grupo, orden
    (1,  N'Ventas',                          1, 0, 1, 1),
    (2,  N'Costo de Ventas',                 2, 0, 2, 2),
    (3,  N'Costo de Comida',                 3, 1, 2, 3),
    (4,  N'Empaque',                         3, 0, 2, 4),
    (5,  N'Flete',                           3, 0, 2, 5),
    (6,  N'Utilidad Bruta',                  2, 0, 3, 6),
    (7,  N'Gastos Controlables',             2, 0, 4, 7),
    (8,  N'Empleados Planillas',             4, 0, 4, 8),
    (9,  N'Servicios Públicos',              4, 0, 4, 9),
    (10, N'Mantenimiento',                   4, 0, 4, 10),
    (11, N'Suministros y Cristalería',       4, 0, 4, 11),
    (12, N'Limpieza y Operación',            4, 0, 4, 12),
    (13, N'Papelería y Útiles',              4, 0, 4, 13),
    (14, N'Uniformes',                       4, 0, 4, 14),
    (15, N'Servicios Externos',              4, 0, 4, 15),
    (16, N'Viajes y Viáticos',               4, 0, 4, 16),
    (17, N'Seguridad Industrial',            4, 0, 4, 17),
    (18, N'Gastos Mercadeo',                 3, 0, 4, 18),
    (19, N'Motivación y Reconocimiento',     4, 0, 4, 19),
    (20, N'Capacitación',                    4, 0, 4, 20),
    (21, N'Utilidad Después de Controlables',2, 0, 5, 21)
) AS origen (id_rubro, nombre, tipo_dato, aplica_menu, id_grupo, orden)
ON destino.rub_id_negocio = @idNegocio AND destino.rub_id_reporte = @idReporte AND destino.rub_id_rubro = origen.id_rubro
WHEN MATCHED THEN
    UPDATE SET rub_nombre = origen.nombre, rub_tipo_dato = origen.tipo_dato, rub_aplica_menu = origen.aplica_menu,
        rub_id_grupo = origen.id_grupo, rub_orden = origen.orden
WHEN NOT MATCHED THEN
    INSERT (rub_id_negocio, rub_id_reporte, rub_id_rubro, rub_nombre, rub_tipo_dato, rub_aplica_menu, rub_id_grupo, rub_orden, rub_id_estado)
    VALUES (@idNegocio, @idReporte, origen.id_rubro, origen.nombre, origen.tipo_dato, origen.aplica_menu, origen.id_grupo, origen.orden, 1);
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── 4. Rubro Menú ───────────────────────────────────────────────────────────
-- Desglose de Costo de Comida (rubro 3) — el único rubro con aplica_menu = 1.
-- "Controlables" (id 8) no es una línea capturable del desglose, es el total de
-- las otras 7 — se removió del catálogo (queda fuera del desplegable).

MERGE [pyl].[prg_rbm_rubro_menu] AS destino
USING (VALUES
    (3, 1, N'Pmix'),
    (3, 2, N'Desperdicio'),
    (3, 3, N'Devolución'),
    (3, 4, N'Dif. Rendimiento'),
    (3, 5, N'Dif. Unitario'),
    (3, 6, N'Condimentos'),
    (3, 7, N'Ajustes')
) AS origen (id_rubro, id_rubromenu, nombre)
ON destino.rbm_id_negocio = @idNegocio AND destino.rbm_id_reporte = @idReporte
   AND destino.rbm_id_rubro = origen.id_rubro AND destino.rbm_id_rubromenu = origen.id_rubromenu
WHEN MATCHED THEN
    UPDATE SET rbm_nombre = origen.nombre
WHEN NOT MATCHED THEN
    INSERT (rbm_id_negocio, rbm_id_reporte, rbm_id_rubro, rbm_id_rubromenu, rbm_nombre, rbm_orden, rbm_id_estado)
    VALUES (@idNegocio, @idReporte, origen.id_rubro, origen.id_rubromenu, origen.nombre, origen.id_rubromenu, 1);
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- Limpieza: quita la fila "Controlables" (id 8) si ya había quedado sembrada de
-- una corrida anterior del script (el MERGE de arriba no borra filas que ya no
-- vienen en el USING — solo inserta/actualiza). Primero los detalles capturados
-- que la referencian (si alguna tienda ya guardó una línea con ese id_rubromenu
-- durante pruebas), si no la FK no deja borrar el catálogo.
DELETE FROM [pyl].[prg_pdm_plan_detalle_menu]
WHERE pdm_id_negocio = @idNegocio AND pdm_id_reporte = @idReporte
  AND pdm_id_rubro = 3 AND pdm_id_rubromenu = 8;

DELETE FROM [pyl].[prg_rbm_rubro_menu]
WHERE rbm_id_negocio = @idNegocio AND rbm_id_reporte = @idReporte
  AND rbm_id_rubro = 3 AND rbm_id_rubromenu = 8;
GO

DECLARE @idNegocio INT = 1;
DECLARE @idReporte INT = 1;

-- ─── 5. Rubro Cálculo ────────────────────────────────────────────────────────
-- Costo de Ventas = Costo de Comida + Empaque + Flete
-- Utilidad Bruta = Ventas − Costo de Ventas
-- Gastos Controlables = suma de las 13 líneas controlables
-- Utilidad Después de Controlables = Utilidad Bruta − Gastos Controlables

MERGE [pyl].[prg_rbc_rubro_calculo] AS destino
USING (VALUES
    (2,  3,  1),
    (2,  4,  1),
    (2,  5,  1),
    (6,  1,  1),
    (6,  2, -1),
    (7,  8,  1),
    (7,  9,  1),
    (7,  10, 1),
    (7,  11, 1),
    (7,  12, 1),
    (7,  13, 1),
    (7,  14, 1),
    (7,  15, 1),
    (7,  16, 1),
    (7,  17, 1),
    (7,  18, 1),
    (7,  19, 1),
    (7,  20, 1),
    (21, 6,  1),
    (21, 7, -1)
) AS origen (id_rubro, id_rubro_referencia, signo)
ON destino.rbc_id_negocio = @idNegocio AND destino.rbc_id_reporte = @idReporte
   AND destino.rbc_id_rubro = origen.id_rubro AND destino.rbc_id_rubro_referencia = origen.id_rubro_referencia
WHEN NOT MATCHED THEN
    INSERT (rbc_id_negocio, rbc_id_reporte, rbc_id_rubro, rbc_id_rubro_referencia, rbc_signo_operacion, rbc_id_estado)
    VALUES (@idNegocio, @idReporte, origen.id_rubro, origen.id_rubro_referencia, origen.signo, 1);
GO
