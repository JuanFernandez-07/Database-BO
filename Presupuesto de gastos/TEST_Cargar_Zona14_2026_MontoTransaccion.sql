-- =============================================
-- Script: TEST_Cargar_Zona14_2026_MontoTransaccion
-- Modulo: Presupuesto de Gastos (P&L Tiendas) - PRUEBA en DEV
-- Descripcion: Carga SOLO tienda 100 (Zona 14), SOLO anio 2026, a
--              pyl.vta_rme_reporte_mes, usando la columna I
--              (MONTO_TRANSACCION, monto real - NO en miles) de
--              data-6.csv, para revisar como se ve en pantalla antes de
--              decidir si se recarga todo con esta escala.
--              OJO: esto SOBREESCRIBE agosto 2026 de tienda 100 que ya
--              habia quedado cargado en 005 con la escala 'MONTO (MILES)'
--              (~1000x mas pequena) - mismo mes/tienda/rubro, mismo MERGE
--              key, entonces el valor de agosto va a saltar de ~647 a
--              ~647,000 para Empleados Planillas, por ejemplo.
--              Ventas (rubro 1), Gastos Controlables (rubros 8-20) y
--              Costo de Venta (rubros 3,4,5), meses con dato disponible
--              (Oct/Nov/Dic no traen MONTO_TRANSACCION todavia).
-- Base: sm_backoffice
-- Fecha: 2026-09-23
-- =============================================

USE [sm_backoffice];
GO

-- Lote 1 (9 filas) - Ventas, tienda 100, 2026 (MONTO_TRANSACCION)
MERGE [pyl].[vta_rme_reporte_mes] AS destino
USING (VALUES
    (1, 1, 100, 2026, 1, 1, N'Ventas', 1, 0, 1, 1, 1, 3272264.80, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 1, N'Ventas', 1, 0, 1, 1, 1, 2971772.87, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 1, N'Ventas', 1, 0, 1, 1, 1, 3157634.36, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 1, N'Ventas', 1, 0, 1, 1, 1, 3115386.97, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 1, N'Ventas', 1, 0, 1, 1, 1, 3469026.91, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 1, N'Ventas', 1, 0, 1, 1, 1, 3059084.93, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 1, N'Ventas', 1, 0, 1, 1, 1, 3241978.94, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 1, N'Ventas', 1, 0, 1, 1, 1, 3476505.20, 1.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 1, N'Ventas', 1, 0, 1, 1, 1, 2507225.62, 1.0000, 0.0000, 0.0000, 0.00, 0.0000)
) AS origen (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
ON destino.rme_id_negocio = origen.rme_id_negocio AND destino.rme_id_reporte = origen.rme_id_reporte
   AND destino.rme_tienda_codigo = origen.rme_tienda_codigo AND destino.rme_anio = origen.rme_anio
   AND destino.rme_mes = origen.rme_mes AND destino.rme_id_rubro = origen.rme_id_rubro
WHEN MATCHED THEN
    UPDATE SET rme_nombre = origen.rme_nombre, rme_tipo_dato = origen.rme_tipo_dato,
        rme_aplica_menu = origen.rme_aplica_menu, rme_id_grupo = origen.rme_id_grupo,
        rme_orden = origen.rme_orden, rme_id_estado = origen.rme_id_estado,
        rme_monto = origen.rme_monto, rme_pct = origen.rme_pct,
        rme_pct_ly = origen.rme_pct_ly, rme_pct_diferencia = origen.rme_pct_diferencia,
        rme_base_monto = origen.rme_base_monto, rme_base_pct = origen.rme_base_pct
WHEN NOT MATCHED THEN
    INSERT (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
    VALUES (origen.rme_id_negocio, origen.rme_id_reporte, origen.rme_tienda_codigo, origen.rme_anio, origen.rme_mes, origen.rme_id_rubro, origen.rme_nombre, origen.rme_tipo_dato, origen.rme_aplica_menu, origen.rme_id_grupo, origen.rme_orden, origen.rme_id_estado, origen.rme_monto, origen.rme_pct, origen.rme_pct_ly, origen.rme_pct_diferencia, origen.rme_base_monto, origen.rme_base_pct);
GO

-- Lote 2 (98 filas) - Gastos Controlables, tienda 100, 2026 (MONTO_TRANSACCION)
MERGE [pyl].[vta_rme_reporte_mes] AS destino
USING (VALUES
    (1, 1, 100, 2026, 1, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 688209.49, 0.2103, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 88651.26, 0.0271, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 25376.38, 0.0078, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 6672.44, 0.0020, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 20942.41, 0.0064, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 4487.51, 0.0014, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 14, N'Uniformes', 4, 0, 4, 14, 1, 4044.75, 0.0012, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 22931.55, 0.0070, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 551.34, 0.0002, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 71809.00, 0.0219, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 78.86, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 661661.21, 0.2226, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 73201.56, 0.0246, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 68497.80, 0.0230, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 15453.45, 0.0052, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 24176.31, 0.0081, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 978.88, 0.0003, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 14, N'Uniformes', 4, 0, 4, 14, 1, 2587.34, 0.0009, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 25925.77, 0.0087, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 4285.72, 0.0014, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 50907.53, 0.0171, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 86.96, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 666409.72, 0.2110, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 78734.50, 0.0249, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 90940.62, 0.0288, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 38488.22, 0.0122, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 25790.80, 0.0082, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 2649.18, 0.0008, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 14, N'Uniformes', 4, 0, 4, 14, 1, 3205.08, 0.0010, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 24520.87, 0.0078, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 2767.86, 0.0009, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 58630.78, 0.0186, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 270.94, 0.0001, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 701443.13, 0.2252, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 80544.89, 0.0259, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 55213.92, 0.0177, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 16696.24, 0.0054, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 18712.86, 0.0060, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 3437.21, 0.0011, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 14, N'Uniformes', 4, 0, 4, 14, 1, 1154.46, 0.0004, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 24520.87, 0.0079, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 3022.32, 0.0010, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 33812.52, 0.0109, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 128.07, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 20, N'Capacitación', 4, 0, 4, 20, 1, 1094.43, 0.0004, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 674496.58, 0.1944, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 79074.34, 0.0228, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 75180.63, 0.0217, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 10817.75, 0.0031, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 23003.59, 0.0066, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 2975.82, 0.0009, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 14, N'Uniformes', 4, 0, 4, 14, 1, 1639.88, 0.0005, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 19520.87, 0.0056, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 6892.88, 0.0020, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 74084.08, 0.0214, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 35.13, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 20, N'Capacitación', 4, 0, 4, 20, 1, 280.20, 0.0001, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 631864.66, 0.2066, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 91762.32, 0.0300, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 53385.88, 0.0175, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 7931.71, 0.0026, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 29522.09, 0.0097, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 4079.63, 0.0013, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 14, N'Uniformes', 4, 0, 4, 14, 1, 2283.93, 0.0007, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 19520.87, 0.0064, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 8366.08, 0.0027, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 65855.99, 0.0215, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 19, N'Motivación y Reconocimiento', 4, 0, 4, 19, 1, 42.33, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 615168.45, 0.1898, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 98923.53, 0.0305, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 50149.77, 0.0155, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 6137.43, 0.0019, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 23454.19, 0.0072, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 2550.95, 0.0008, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 14, N'Uniformes', 4, 0, 4, 14, 1, 565.00, 0.0002, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 19520.87, 0.0060, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 3428.62, 0.0011, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 67677.31, 0.0209, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 647672.94, 0.1863, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 98733.64, 0.0284, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 82008.11, 0.0236, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 14229.85, 0.0041, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 21903.87, 0.0063, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 3273.64, 0.0009, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 14, N'Uniformes', 4, 0, 4, 14, 1, 2294.51, 0.0007, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 19520.85, 0.0056, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 17, N'Seguridad Industrial', 4, 0, 4, 17, 1, 4973.22, 0.0014, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 89916.88, 0.0259, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 20, N'Capacitación', 4, 0, 4, 20, 1, 0.00, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 8, N'Empleados Planillas', 4, 0, 4, 8, 1, 330129.68, 0.1317, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 9, N'Servicios Publicos', 4, 0, 4, 9, 1, 86719.01, 0.0346, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 10, N'Mantenimiento', 4, 0, 4, 10, 1, 3355.87, 0.0013, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 11, N'Suministros y Cristalería', 4, 0, 4, 11, 1, 216.02, 0.0001, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 12, N'Limpieza y Operación', 4, 0, 4, 12, 1, 708.24, 0.0003, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 13, N'Papelería y Útiles', 4, 0, 4, 13, 1, 20.98, 0.0000, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 15, N'Servicios Externos', 4, 0, 4, 15, 1, 19141.40, 0.0076, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 16, N'Viajes y Viáticos', 4, 0, 4, 16, 1, 1680.00, 0.0007, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 18, N'Gastos Mercadeo', 3, 0, 4, 18, 1, 8797.37, 0.0035, 0.0000, 0.0000, 0.00, 0.0000)
) AS origen (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
ON destino.rme_id_negocio = origen.rme_id_negocio AND destino.rme_id_reporte = origen.rme_id_reporte
   AND destino.rme_tienda_codigo = origen.rme_tienda_codigo AND destino.rme_anio = origen.rme_anio
   AND destino.rme_mes = origen.rme_mes AND destino.rme_id_rubro = origen.rme_id_rubro
WHEN MATCHED THEN
    UPDATE SET rme_nombre = origen.rme_nombre, rme_tipo_dato = origen.rme_tipo_dato,
        rme_aplica_menu = origen.rme_aplica_menu, rme_id_grupo = origen.rme_id_grupo,
        rme_orden = origen.rme_orden, rme_id_estado = origen.rme_id_estado,
        rme_monto = origen.rme_monto, rme_pct = origen.rme_pct,
        rme_pct_ly = origen.rme_pct_ly, rme_pct_diferencia = origen.rme_pct_diferencia,
        rme_base_monto = origen.rme_base_monto, rme_base_pct = origen.rme_base_pct
WHEN NOT MATCHED THEN
    INSERT (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
    VALUES (origen.rme_id_negocio, origen.rme_id_reporte, origen.rme_tienda_codigo, origen.rme_anio, origen.rme_mes, origen.rme_id_rubro, origen.rme_nombre, origen.rme_tipo_dato, origen.rme_aplica_menu, origen.rme_id_grupo, origen.rme_orden, origen.rme_id_estado, origen.rme_monto, origen.rme_pct, origen.rme_pct_ly, origen.rme_pct_diferencia, origen.rme_base_monto, origen.rme_base_pct);
GO

-- Lote 3 (25 filas) - Costo de Venta, tienda 100, 2026 (MONTO_TRANSACCION)
MERGE [pyl].[vta_rme_reporte_mes] AS destino
USING (VALUES
    (1, 1, 100, 2026, 1, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1314677.09, 0.4018, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 4, N'Empaque', 3, 0, 2, 4, 1, 51828.58, 0.0158, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 1, 5, N'Flete', 3, 0, 2, 5, 1, 99397.90, 0.0304, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1134720.61, 0.3818, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 4, N'Empaque', 3, 0, 2, 4, 1, 42619.04, 0.0143, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 2, 5, N'Flete', 3, 0, 2, 5, 1, 89129.72, 0.0300, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1179081.27, 0.3734, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 4, N'Empaque', 3, 0, 2, 4, 1, 54563.47, 0.0173, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 3, 5, N'Flete', 3, 0, 2, 5, 1, 95116.74, 0.0301, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1186263.94, 0.3808, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 4, N'Empaque', 3, 0, 2, 4, 1, 48155.61, 0.0155, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 4, 5, N'Flete', 3, 0, 2, 5, 1, 93759.07, 0.0301, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1320736.10, 0.3807, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 4, N'Empaque', 3, 0, 2, 4, 1, 49614.36, 0.0143, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 5, 5, N'Flete', 3, 0, 2, 5, 1, 103178.91, 0.0297, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1145038.37, 0.3743, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 4, N'Empaque', 3, 0, 2, 4, 1, 49423.32, 0.0162, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 6, 5, N'Flete', 3, 0, 2, 5, 1, 92135.37, 0.0301, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1153748.85, 0.3559, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 4, N'Empaque', 3, 0, 2, 4, 1, 59877.57, 0.0185, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 7, 5, N'Flete', 3, 0, 2, 5, 1, 97521.00, 0.0301, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 3, N'Costo de Comida', 3, 1, 2, 3, 1, 1235361.99, 0.3553, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 4, N'Empaque', 3, 0, 2, 4, 1, 61782.58, 0.0178, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 8, 5, N'Flete', 3, 0, 2, 5, 1, 105584.46, 0.0304, 0.0000, 0.0000, 0.00, 0.0000),
    (1, 1, 100, 2026, 9, 4, N'Empaque', 3, 0, 2, 4, 1, 1067.84, 0.0004, 0.0000, 0.0000, 0.00, 0.0000)
) AS origen (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
ON destino.rme_id_negocio = origen.rme_id_negocio AND destino.rme_id_reporte = origen.rme_id_reporte
   AND destino.rme_tienda_codigo = origen.rme_tienda_codigo AND destino.rme_anio = origen.rme_anio
   AND destino.rme_mes = origen.rme_mes AND destino.rme_id_rubro = origen.rme_id_rubro
WHEN MATCHED THEN
    UPDATE SET rme_nombre = origen.rme_nombre, rme_tipo_dato = origen.rme_tipo_dato,
        rme_aplica_menu = origen.rme_aplica_menu, rme_id_grupo = origen.rme_id_grupo,
        rme_orden = origen.rme_orden, rme_id_estado = origen.rme_id_estado,
        rme_monto = origen.rme_monto, rme_pct = origen.rme_pct,
        rme_pct_ly = origen.rme_pct_ly, rme_pct_diferencia = origen.rme_pct_diferencia,
        rme_base_monto = origen.rme_base_monto, rme_base_pct = origen.rme_base_pct
WHEN NOT MATCHED THEN
    INSERT (rme_id_negocio, rme_id_reporte, rme_tienda_codigo, rme_anio, rme_mes, rme_id_rubro, rme_nombre, rme_tipo_dato, rme_aplica_menu, rme_id_grupo, rme_orden, rme_id_estado, rme_monto, rme_pct, rme_pct_ly, rme_pct_diferencia, rme_base_monto, rme_base_pct)
    VALUES (origen.rme_id_negocio, origen.rme_id_reporte, origen.rme_tienda_codigo, origen.rme_anio, origen.rme_mes, origen.rme_id_rubro, origen.rme_nombre, origen.rme_tipo_dato, origen.rme_aplica_menu, origen.rme_id_grupo, origen.rme_orden, origen.rme_id_estado, origen.rme_monto, origen.rme_pct, origen.rme_pct_ly, origen.rme_pct_diferencia, origen.rme_base_monto, origen.rme_base_pct);
GO
