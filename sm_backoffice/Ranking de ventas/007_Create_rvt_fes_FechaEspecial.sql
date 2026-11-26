-- Ejecutar en la base sm_backoffice (después de 006).

USE sm_backoffice;
GO
-- Fechas especiales del Ranking de Ventas (01/11, 24/12, 06/01, 10/05…), por negocio.
-- Reemplazan a los períodos Hoy / Semana / Mes / Año en la pantalla.
--   * TY = ese mes y día del año en curso; LY = el mismo mes y día del año anterior.
--   * Si la fecha aún no llega este año, el ranking la muestra con venta en 0.
--   * Al elegir una fecha solo aparecen las tiendas (y países) de los negocios que la tienen
--     configurada y activa.
-- Sin columna Id: la llave es negocio + mes + día (no se puede repetir la fecha en un negocio).

IF OBJECT_ID('vta.rvt_fes_fecha_especial', 'U') IS NULL
    CREATE TABLE vta.rvt_fes_fecha_especial (
        fes_codigo_neg INT           NOT NULL,
        fes_mes        TINYINT       NOT NULL,
        fes_dia        TINYINT       NOT NULL,
        fes_nombre     NVARCHAR(100) NOT NULL,
        fes_estado     BIT           NOT NULL CONSTRAINT DF_rvt_fes_fecha_especial_estado DEFAULT (1),
        CONSTRAINT PK_rvt_fes_fecha_especial PRIMARY KEY (fes_codigo_neg, fes_mes, fes_dia),
        CONSTRAINT CK_rvt_fes_fecha_especial_mes CHECK (fes_mes BETWEEN 1 AND 12),
        CONSTRAINT CK_rvt_fes_fecha_especial_dia CHECK (fes_dia BETWEEN 1 AND 31)
    );
GO

-- ─── Fechas iniciales (AJUSTAR: negocios y nombres) ─────────────────────────────────
-- Negocios: 1 San Martín Guatemala, 2 San Martín El Salvador, 3 San Martín USA,
--           4 Cielito Lindo Guatemala, 5 Cielito Lindo Grill Guatemala.
-- Solo inserta las que no existan. 
INSERT INTO vta.rvt_fes_fecha_especial (fes_codigo_neg, fes_mes, fes_dia, fes_nombre)
SELECT v.neg, v.mes, v.dia, v.nombre
FROM (VALUES
    (1, 11,  1, N'Día de Todos los Santos'),
    (1, 12, 24, N'Nochebuena'),
    (1,  1,  6, N'Día de Reyes'),
    (1,  5, 10, N'Día de la Madre'),
    (1,  9, 15, N'Día de la Independencia'),
    (1,  2, 14, N'Día del Cariño'),
    (2, 11,  1, N'Día de Todos los Santos'),
    (2, 12, 24, N'Nochebuena'),
    (2,  1,  6, N'Día de Reyes'),
    (2,  5, 10, N'Día de la Madre'),
    (2,  2, 14, N'Día del Cariño'),
    (3, 11,  1, N'Día de Todos los Santos'),
    (3, 12, 24, N'Nochebuena'),
    (3,  1,  6, N'Día de Reyes'),
    (3,  5, 10, N'Día de la Madre'),
    (3,  2, 14, N'Día del Cariño')
) AS v(neg, mes, dia, nombre)
WHERE NOT EXISTS (
    SELECT 1 FROM vta.rvt_fes_fecha_especial f
    WHERE f.fes_codigo_neg = v.neg AND f.fes_mes = v.mes AND f.fes_dia = v.dia);
GO

-- Permiso de lectura para la API (mismo usuario que SmBackofficeRankingVentasConnection).
-- AJUSTAR el usuario antes de ejecutar:
-- GRANT SELECT ON vta.rvt_fes_fecha_especial TO [<USUARIO_API_RANKING>];

SELECT * FROM vta.rvt_fes_fecha_especial ORDER BY fes_codigo_neg, fes_mes, fes_dia;
GO
