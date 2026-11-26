-- Ejecutar en la base sm_backoffice (después de 007).

USE sm_backoffice;
GO
-- LY "hasta la hora actual": cuando la fecha consultada es HOY, el año anterior se muestra solo con
-- los checks cerrados hasta la misma hora y minuto (hora de Guatemala para todas las tiendas).
-- El LY se consulta directo en estas vistas (no en la tabla resumen, que es por día completo).
--
-- Se agrega minuto_del_dia = hora * 60 + minuto (minutos desde la medianoche, sin segundos):
--   * FiscalInvoice (GT / SV): hora y minuto de SysDate.
--   * RankingGNDSALE (Dallas): CLOSEHOUR y CLOSEMIN.
-- Los checks después de medianoche no se tratan aparte (decisión de negocio: no debería haberlos).
-- Los SPs del job no cambian: no usan esta columna.

CREATE OR ALTER VIEW vta.vw_rvd_fiscal_invoice_neto
AS
SELECT
    CONVERT(INT, fi.LC_UNIT)  AS tienda,
    CONVERT(DATE, fi.LC_DOB)  AS fecha,
    CASE
        WHEN fi.TermId BETWEEN 1  AND 5  THEN 'panaderia'
        WHEN fi.TermId BETWEEN 6  AND 15 THEN 'restaurante'
        ELSE 'otros'  -- Café (30-34), Delivery (35-36), Autoservicio (37-38) y cualquier otro
    END AS categoria,
    CASE fi.DocTypeId WHEN 10 THEN 1 ELSE 0 END                               AS es_reembolso,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TaxableAmount, 0) AS venta_sin_iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TotalTax, 0)      AS iva,
    CASE fi.DocTypeId WHEN 10 THEN -1 ELSE 1 END * ISNULL(fi.TotalTxn, 0)      AS venta_con_iva,
    ISNULL(fi.TaxableAmount, 0)                                                AS monto_sin_iva_documento,
    DATEPART(HOUR, fi.SysDate) * 60 + DATEPART(MINUTE, fi.SysDate)             AS minuto_del_dia,
    fi.FechaImportacion
FROM sm_pos.dbo.FiscalInvoice fi
WHERE fi.DocTypeId IN (1, 10);
GO

CREATE OR ALTER VIEW vta.vw_rvd_gndsale_neto
AS
SELECT
    g.LC_UNIT AS tienda,
    g.LC_DOB  AS fecha,
    CASE
        WHEN g.TYPEID IN (603, 1) THEN 'restaurante'
        WHEN g.TYPEID = 2         THEN 'panaderia'
        ELSE 'otros'
    END AS categoria,
    0                         AS es_reembolso,
    -- GNDSALE agrega por check y categoría: no se cuentan documentos (rvd_cantidad_ventas = 0).
    0                         AS cuenta_venta,
    ISNULL(g.AMOUNT, 0)       AS venta_sin_iva,
    CAST(0 AS DECIMAL(18, 2)) AS iva,
    ISNULL(g.AMOUNT, 0)       AS venta_con_iva,
    CAST(0 AS DECIMAL(18, 2)) AS monto_sin_iva_documento,
    g.CLOSEHOUR * 60 + g.CLOSEMIN AS minuto_del_dia,
    g.FechaImportacion
FROM sm_pos.dbo.RankingGNDSALE g
WHERE g.TYPE = 52
  AND g.TYPEID <> 74;  -- Propina
GO

CREATE OR ALTER VIEW vta.vw_rvd_venta_neta
AS
SELECT 'fiscal_invoice' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       1 - es_reembolso AS cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, monto_sin_iva_documento, minuto_del_dia, FechaImportacion
FROM vta.vw_rvd_fiscal_invoice_neto
UNION ALL
SELECT 'gndsale' AS fuente,
       tienda, fecha, categoria, es_reembolso,
       cuenta_venta,
       venta_sin_iva, iva, venta_con_iva, monto_sin_iva_documento, minuto_del_dia, FechaImportacion
FROM vta.vw_rvd_gndsale_neto;
GO

-- ─── Fecha especial 15/09 del negocio 1 (Día de la Independencia) ───────────────────
-- Ya está en el 007; esto es por si el 007 se ejecutó antes de agregarla. No la duplica.
INSERT INTO vta.rvt_fes_fecha_especial (fes_codigo_neg, fes_mes, fes_dia, fes_nombre)
SELECT 1, 9, 15, N'Día de la Independencia'
WHERE NOT EXISTS (
    SELECT 1 FROM vta.rvt_fes_fecha_especial
    WHERE fes_codigo_neg = 1 AND fes_mes = 9 AND fes_dia = 15);
GO

-- ─── Permisos de la API (AJUSTAR el usuario antes de ejecutar) ──────────────────────
-- La API ahora lee la vista unificada. Una vista en sm_backoffice que lee sm_pos NO le pasa el
-- permiso al usuario: el usuario de SmBackofficeRankingVentasConnection debe existir también en
-- sm_pos y tener SELECT sobre las dos tablas de origen.
-- GRANT SELECT ON vta.vw_rvd_venta_neta TO [<USUARIO_API_RANKING>];
-- USE sm_pos;
-- GRANT SELECT ON dbo.FiscalInvoice  TO [<USUARIO_API_RANKING>];
-- GRANT SELECT ON dbo.RankingGNDSALE TO [<USUARIO_API_RANKING>];

-- Verificación: minuto_del_dia entre 0 y 1439 en ambas fuentes.
SELECT fuente, MIN(minuto_del_dia) AS minimo, MAX(minuto_del_dia) AS maximo, COUNT(*) AS filas
FROM vta.vw_rvd_venta_neta
GROUP BY fuente;
GO
