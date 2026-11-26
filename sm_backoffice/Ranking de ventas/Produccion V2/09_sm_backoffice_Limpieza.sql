-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE ███
-- PRODUCCIÓN V2 · Limpieza: quita lo que el Ranking ya no usa desde el script 08.
-- ⚠ Correr SOLO después de publicar la API nueva en los dos webapi (actual y público): la API anterior
--   todavía lee vta.vw_rvd_venta_neta y dejaría de funcionar.
-- Idempotente: lo que ya no existe se salta.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Se borra (sm_backoffice):
--   vta.vw_rvd_venta_neta           LY de la API anterior (FiscalInvoice + RankingGNDSALE)
--   vta.vw_rvd_fiscal_invoice_neto  la usaba solo vw_rvd_venta_neta
--   vta.vw_rvd_gndsale_neto         Dallas antes de leerse por KIO
-- Se quita (sm_pos), si existe:
--   el permiso de lectura del usuario de la instalación pública sobre FiscalInvoice y RankingGNDSALE.
--   La carga del histórico (vta.rvd_CargarHistoricoFecha) las sigue leyendo con el usuario de quien la corre.
-- NO se tocan las tablas FiscalInvoice y RankingGNDSALE ni sus procesos de carga: no son del Ranking y
-- pueden usarlas otros módulos.

USE sm_backoffice;
GO

-- La función solo nombraba las vistas en un comentario: se recrea igual, sin esa mención, para que la
-- verificación no la cuente como un uso.
CREATE OR ALTER FUNCTION vta.rvd_CategoriaPorTerminal (@term_id INT)
RETURNS TABLE
AS
RETURN
    SELECT CASE
               WHEN @term_id BETWEEN 1 AND 5  THEN 'panaderia'
               WHEN @term_id BETWEEN 6 AND 15 THEN 'restaurante'
               ELSE 'otros'  -- Café (30-34), Delivery (35-36), Autoservicio (37-38) y cualquier otro
           END AS categoria;
GO

-- ─── 0. Verificación previa ─────────────────────────────────────────────────────────
-- Ningún SP, vista o función debe usar las vistas que se borran (fuera de ellas mismas).
DECLARE @usos NVARCHAR(4000) = (
    SELECT STRING_AGG(OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id), ', ')
    FROM sys.sql_modules m
    WHERE (m.definition LIKE '%vw_rvd_venta_neta%'
        OR m.definition LIKE '%vw_rvd_fiscal_invoice_neto%'
        OR m.definition LIKE '%vw_rvd_gndsale_neto%')
      AND OBJECT_NAME(m.object_id) NOT IN ('vw_rvd_venta_neta', 'vw_rvd_fiscal_invoice_neto', 'vw_rvd_gndsale_neto'));

IF @usos IS NOT NULL
BEGIN
    RAISERROR(N'No se borró nada: estos objetos todavía usan las vistas: %s', 16, 1, @usos);
    SET NOEXEC ON;
END;
GO

-- ¿La API anterior las sigue consultando? Sesiones abiertas leyendo la vista del LY (debe dar 0 filas).
-- Si devuelve filas, la API anterior sigue publicada en algún webapi: detener aquí.
SELECT s.session_id, s.host_name, s.program_name, s.login_name
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE t.text LIKE '%vw_rvd_venta_neta%'
  AND r.session_id <> @@SPID;
GO

-- ─── 1. Vistas ──────────────────────────────────────────────────────────────────────
DROP VIEW IF EXISTS vta.vw_rvd_venta_neta;
DROP VIEW IF EXISTS vta.vw_rvd_fiscal_invoice_neto;
DROP VIEW IF EXISTS vta.vw_rvd_gndsale_neto;
GO

-- ─── 2. Permisos en sm_pos del usuario público ──────────────────────────────────────
-- ANTES DE EJECUTAR esta sección: reemplazar <USUARIO_RANKING_PUBLICO> (el del script 05).
-- USE sm_pos;
-- REVOKE SELECT ON dbo.FiscalInvoice  FROM [<USUARIO_RANKING_PUBLICO>];
-- REVOKE SELECT ON dbo.RankingGNDSALE FROM [<USUARIO_RANKING_PUBLICO>];
-- GO

SET NOEXEC OFF;
GO

-- ─── 3. Verificación ────────────────────────────────────────────────────────────────
-- 0 filas: las vistas ya no existen.
SELECT name FROM sm_backoffice.sys.views
WHERE name IN ('vw_rvd_venta_neta', 'vw_rvd_fiscal_invoice_neto', 'vw_rvd_gndsale_neto');

-- Lo que queda del Ranking en sm_backoffice (referencia).
SELECT o.name, o.type_desc
FROM sm_backoffice.sys.objects o
WHERE SCHEMA_NAME(o.schema_id) = 'vta'
  AND (o.name LIKE 'rvd[_]%' OR o.name LIKE 'rvt[_]%' OR o.name LIKE 'vw[_]rvd[_]%')
ORDER BY o.type_desc, o.name;
GO

-- ─── 4. Opcional (sm_pos): trigger de propina de FiscalInvoice ──────────────────────
-- Solo llenaba FiscalInvoice.Propina para el LY anterior; el Ranking ya no lo usa. Se puede quitar si
-- ningún otro proceso lee esa columna. La columna y sus valores se quedan.
-- USE sm_pos;
-- DROP TRIGGER IF EXISTS dbo.trg_FiscalInvoice_Propina;
