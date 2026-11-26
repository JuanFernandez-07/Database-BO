-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_pos ███
-- Conexión de tiendas · Paso 3: procedimiento del reporte (módulo de Reportes, sm_reportes).
-- Requiere el paso 1 (tabla dbo.TLS_LogConexionTienda). Idempotente.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Lo llama el reporte "BOSLC: Conexión de tiendas" (script 04) con tipo_sql = 2:
--   begin exec [sm_pos].[dbo].[usp_TLS_ReporteConexionTiendas] @FechaIni, @FechaFin end
-- Las fechas filtran por el día de la corrida (tls_ejecucion), las dos inclusive.

USE sm_pos;
GO

CREATE OR ALTER PROCEDURE dbo.usp_TLS_ReporteConexionTiendas
    @FechaIni DATE,
    @FechaFin DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.tls_ejecucion  AS [Corrida],
           l.tls_codigo_tie AS [Tienda],
           CASE l.tls_codigo_neg
               WHEN 1 THEN 'Guatemala'
               WHEN 2 THEN 'El Salvador'
               WHEN 3 THEN 'USA'
               ELSE CONVERT(VARCHAR(10), l.tls_codigo_neg)
           END              AS [Negocio],
           l.tls_ip         AS [Servidor],
           l.tls_estado     AS [Estado],
           l.tls_segundos   AS [Segundos],
           l.tls_mensaje    AS [Motivo]
    FROM dbo.TLS_LogConexionTienda l
    WHERE l.tls_ejecucion >= @FechaIni
      AND l.tls_ejecucion <  DATEADD(DAY, 1, @FechaFin)
    ORDER BY l.tls_ejecucion DESC,
             CASE l.tls_estado WHEN 'ERROR' THEN 0 ELSE 1 END,
             l.tls_codigo_tie;
END;
GO

-- ─── Permiso para el módulo de Reportes ─────────────────────────────────────────────
-- La API ejecuta el reporte con el usuario de ReportsConnection (App_reporte), que en sm_pos
-- recibe sus permisos por el rol db_Dbaserverazure_appreportes. Con EXECUTE sobre el SP basta:
-- la tabla es del mismo dueño (dbo), así que no hace falta SELECT sobre ella.
GRANT EXECUTE ON dbo.usp_TLS_ReporteConexionTiendas TO [db_Dbaserverazure_appreportes];
GO

-- ─── Prueba ─────────────────────────────────────────────────────────────────────────
-- EXEC dbo.usp_TLS_ReporteConexionTiendas @FechaIni = '20261116', @FechaFin = '20261117';
