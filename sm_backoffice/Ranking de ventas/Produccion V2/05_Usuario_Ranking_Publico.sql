-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE. Una sección por base de datos ███
-- PRODUCCIÓN V2 · Usuario de solo lectura de la instalación pública (sm-webapi-ranking-vts).
-- No cambia nada de los usuarios ni de los App Services actuales.
-- ANTES DE EJECUTAR: reemplazar <USUARIO_RANKING_PUBLICO> y <CONTRASENA>.
-- Idempotente, salvo la contraseña: si el login ya existe no se cambia.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Solo puede leer lo que usan el login y el Ranking. Si el filtro de rutas (AccesoPublicoMiddleware)
-- llegara a fallar, este usuario no puede ver Plan de Hornos, Reportes ni P&L, ni escribir nada.

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'<USUARIO_RANKING_PUBLICO>')
    CREATE LOGIN [<USUARIO_RANKING_PUBLICO>] WITH PASSWORD = N'<CONTRASENA>';
GO

-- ─── sm_seguridad (SecurityConnection): login y módulos del usuario ─────────────────
USE sm_seguridad;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<USUARIO_RANKING_PUBLICO>')
    CREATE USER [<USUARIO_RANKING_PUBLICO>] FOR LOGIN [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_usu_usuario        TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_uro_usuario_rol    TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_rol                TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_uti_usuario_tienda TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_rmo_rol_modulo     TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON sct.seg_mod_modulo         TO [<USUARIO_RANKING_PUBLICO>];
GO

-- ─── sm_backoffice_op (DefaultConnection): nombre, moneda y país de los negocios ────
USE sm_backoffice_op;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<USUARIO_RANKING_PUBLICO>')
    CREATE USER [<USUARIO_RANKING_PUBLICO>] FOR LOGIN [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON plh.Vw_plh_neg_Negocios TO [<USUARIO_RANKING_PUBLICO>];
GO

-- ─── sm_backoffice (SmBackofficeConnection y SmBackofficeRankingVentasConnection) ───
USE sm_backoffice;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<USUARIO_RANKING_PUBLICO>')
    CREATE USER [<USUARIO_RANKING_PUBLICO>] FOR LOGIN [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.tie_tienda                  TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.reg_region                  TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.vw_rvd_resumen_ultimo_bloque TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.vw_rvd_venta_neta           TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.rvt_fes_fecha_especial      TO [<USUARIO_RANKING_PUBLICO>];
-- Desde el script 08: el LY sale del resumen completo y la pantalla filtra por la bitácora.
GRANT SELECT ON vta.rvt_rvd_resumen_venta_diaria TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON vta.rvt_lik_log_importacion_kio  TO [<USUARIO_RANKING_PUBLICO>];
GO

-- ─── sm_pos: las vistas de sm_backoffice leen de aquí y ese permiso no se hereda ────
USE sm_pos;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<USUARIO_RANKING_PUBLICO>')
    CREATE USER [<USUARIO_RANKING_PUBLICO>] FOR LOGIN [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON dbo.FiscalInvoice  TO [<USUARIO_RANKING_PUBLICO>];
GRANT SELECT ON dbo.RankingGNDSALE TO [<USUARIO_RANKING_PUBLICO>];
GO

-- ─── Verificación: conectado como <USUARIO_RANKING_PUBLICO> ─────────────────────────
-- Estas deben funcionar:
--   SELECT TOP 1 * FROM sm_seguridad.sct.seg_usu_usuario;
--   SELECT TOP 1 * FROM sm_backoffice_op.plh.Vw_plh_neg_Negocios;
--   SELECT TOP 1 * FROM sm_backoffice.vta.vw_rvd_resumen_ultimo_bloque;
--   SELECT TOP 1 * FROM sm_backoffice.vta.vw_rvd_venta_neta;
-- Esta debe dar error de permiso:
--   SELECT TOP 1 * FROM sm_backoffice_op.plh.plh_pla_planes;
