-- ════════════════════════════════════════════════════════════════════════════════════
-- PRODUCCIÓN · Paso 2 de 5 · Bases: sm_backoffice y sm_pos
-- Permisos del usuario de la API (cadena de conexión SmBackofficeRankingVentasConnection).
-- ════════════════════════════════════════════════════════════════════════════════════
-- ANTES DE EJECUTAR: reemplazar <USUARIO_API_RANKING> por el usuario de base de datos que usa
-- SmBackofficeRankingVentasConnection en producción.
--
-- La API solo LEE:
--   * sm_backoffice: tabla resumen (TY), tabla de control, fechas especiales y la vista unificada
--     vta.vw_rvd_venta_neta (LY hasta la hora actual).
--   * sm_pos: FiscalInvoice y RankingGNDSALE. La vista vive en sm_backoffice pero lee sm_pos, y ese
--     permiso NO se hereda: el usuario debe existir en sm_pos con SELECT sobre ambas tablas.
-- El nombre y país de las tiendas (vta.tie_tienda) los lee otra conexión que ya existe
-- (SmBackofficeConnection).

USE sm_backoffice;
GO

GRANT SELECT ON vta.rvt_rvd_resumen_venta_diaria TO [<USUARIO_API_RANKING>];
GRANT SELECT ON vta.rvt_cpr_control_proceso      TO [<USUARIO_API_RANKING>];
GRANT SELECT ON vta.rvt_fes_fecha_especial       TO [<USUARIO_API_RANKING>];
GRANT SELECT ON vta.vw_rvd_venta_neta            TO [<USUARIO_API_RANKING>];
GO

-- Verificación: debe listar los cuatro SELECT.
SELECT pr.name AS usuario, o.name AS objeto, pe.permission_name, pe.state_desc
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.objects o ON o.object_id = pe.major_id
WHERE o.name IN ('rvt_rvd_resumen_venta_diaria', 'rvt_cpr_control_proceso', 'rvt_fes_fecha_especial', 'vw_rvd_venta_neta');
GO

-- sm_pos: el usuario debe existir en esta base (CREATE USER ... FOR LOGIN ..., si aún no existe).
USE sm_pos;
GO

GRANT SELECT ON dbo.FiscalInvoice  TO [<USUARIO_API_RANKING>];
GRANT SELECT ON dbo.RankingGNDSALE TO [<USUARIO_API_RANKING>];
GO

-- Verificación: debe listar los dos SELECT.
SELECT pr.name AS usuario, o.name AS objeto, pe.permission_name, pe.state_desc
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
JOIN sys.objects o ON o.object_id = pe.major_id
WHERE o.name IN ('FiscalInvoice', 'RankingGNDSALE');
GO
