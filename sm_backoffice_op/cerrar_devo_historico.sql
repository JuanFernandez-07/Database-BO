-- =============================================
-- Housekeeping: cierre retroactivo de DEVO (Cocina + Panadería), TODAS las tiendas.
--
-- Fase 2 (HORNOS-F2-DEVO): el estado de cierre ya NO se infiere de las filas de
-- plh_dev_devoluciones — vive en plh_prc_procesos.prc_devo_panaderia_cerrada /
-- prc_devo_cocina_cerrada (ver 029_DevoCierreFlags.sql y 07_Devolucion.sql).
--
-- Requiere haber corrido antes 029_DevoCierreFlags.sql (si no, falla con
-- "Invalid column name").
--
-- Qué hace: marca cerradas (ambas banderas) TODAS las fechas anteriores a hoy, en
-- todas las tiendas/negocios — sin dejar ningún día de prueba abierto. Hoy queda
-- intacto (nunca se toca @Fecha = hoy).
-- =============================================

USE [sm_backoffice_op];
GO

-- Previsualización — corre esto primero y revisa antes del UPDATE real.
SELECT
    p.prc_codigo_neg,
    p.prc_tienda_codigo,
    COUNT(*)              AS dias_a_cerrar,
    MIN(p.prc_fecha)      AS fecha_mas_antigua,
    MAX(p.prc_fecha)      AS fecha_mas_reciente_a_cerrar
FROM plh.plh_prc_procesos p
WHERE p.prc_fecha < CAST(GETDATE() AS DATE)
  AND (p.prc_devo_panaderia_cerrada = 0 OR p.prc_devo_cocina_cerrada = 0)
GROUP BY p.prc_codigo_neg, p.prc_tienda_codigo
ORDER BY p.prc_codigo_neg, p.prc_tienda_codigo;
GO

-- Cierre real — descomenta y corre después de revisar la previsualización de arriba.
/*
UPDATE plh.plh_prc_procesos
SET prc_devo_panaderia_cerrada = 1,
    prc_devo_cocina_cerrada    = 1
WHERE prc_fecha < CAST(GETDATE() AS DATE);

SELECT @@ROWCOUNT AS filas_cerradas;
*/
GO
