-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███          (2 de 3)
-- Seguridad y navegación propias de smb_react / smb_net — CATÁLOGO
-- ════════════════════════════════════════════════════════════════════════════════════
-- Requiere 01_seg_Estructura.sql confirmado.
--
-- Carga:
--   - Menús, submenús, módulos y submódulos de las pantallas actuales de smb_react.
--     Operaciones → Producción → Plan de Hornos → (9 pantallas). El resto replica los grupos actuales
--     del sidebar; se reorganiza después desde Administración → Seguridad.
--   - 22 permisos: uno "ver" por pantalla (15) + los 7 privilegios numéricos actuales como claves.
--   - Equivalencias path/privilegio anterior → permiso nuevo (las usa 03_seg_Migracion.sql).
-- Los paths no cambian: rutas, RequiereModulo y pre-auth desde smb siguen funcionando.
--
-- Idempotente (busca por nombre, clave y path). Transacción sin COMMIT automático.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

IF OBJECT_ID(N'seg.acc_peq_permiso_equivalencia', N'U') IS NULL
    THROW 50060, 'No existe la estructura del esquema seg. Correr y confirmar primero 01_seg_Estructura.sql.', 1;

DECLARE @usuarioScript VARCHAR(100) = 'SCRIPT';

-- ─── Datos ───────────────────────────────────────────────────────────────────

DECLARE @menus TABLE (nombre NVARCHAR(150) PRIMARY KEY, descripcion NVARCHAR(300), orden INT NOT NULL);
INSERT INTO @menus (nombre, descripcion, orden) VALUES
    (N'Operaciones',       N'Operación de tiendas y producción', 1),
    (N'Reportes',          N'Reportes',                          2),
    (N'Gestión de Placas', N'Gestión de placas',                 3),
    (N'Ventas',            N'Ventas',                            4),
    (N'P&L',               N'Presupuesto y resultados',          5),
    (N'Administración',    N'Administración del sistema',        6);

DECLARE @submenus TABLE (menu NVARCHAR(150), nombre NVARCHAR(150), orden INT NOT NULL, PRIMARY KEY (menu, nombre));
INSERT INTO @submenus (menu, nombre, orden) VALUES
    (N'Operaciones', N'Producción', 1);

-- path = sct.seg_mod_modulo.mod_path del modelo anterior; pri_anterior NULL = acceso a la pantalla
DECLARE @permisos TABLE (
    clave        VARCHAR(150)  PRIMARY KEY,
    nombre       NVARCHAR(150) NOT NULL,
    grupo        NVARCHAR(100) NOT NULL,
    path         NVARCHAR(200) NOT NULL,
    pri_anterior INT           NULL
);
INSERT INTO @permisos (clave, nombre, grupo, path, pri_anterior) VALUES
    -- Pantallas
    ('plan-hornos.aph.ver',              N'Ver Plan de Hornos',              N'Plan de Hornos', N'/plan-hornos/aph',              NULL),
    ('plan-hornos.pedido-cocina.ver',    N'Ver Pedido Cocina',               N'Plan de Hornos', N'/plan-hornos/pedido-cocina',    NULL),
    ('plan-hornos.proceso-hornos.ver',   N'Ver Proceso de Hornos',           N'Plan de Hornos', N'/plan-hornos/proceso-hornos',   NULL),
    ('plan-hornos.auxiliar.ver',         N'Ver Recepción de Horneado',       N'Plan de Hornos', N'/plan-hornos/auxiliar',         NULL),
    ('plan-hornos.formato-rotacion.ver', N'Ver Control de Repostería',       N'Plan de Hornos', N'/plan-hornos/formato-rotacion', NULL),
    ('plan-hornos.devolucion.ver',       N'Ver Devolución',                  N'Plan de Hornos', N'/plan-hornos/devolucion',       NULL),
    ('plan-hornos.motor-calculo.ver',    N'Ver Motor de Cálculo',            N'Plan de Hornos', N'/plan-hornos/motor-calculo',    NULL),
    ('plan-hornos.control.ver',          N'Ver Control',                     N'Plan de Hornos', N'/plan-hornos/control',          NULL),
    ('plan-hornos.parametrizacion.ver',  N'Ver Parametrización de Tiendas',  N'Plan de Hornos', N'/plan-hornos/parametrizacion',  NULL),
    ('reportes.ver',                     N'Ver Reportes',                    N'Reportes',       N'/reportes',                     NULL),
    ('gestion-placas.ver',               N'Ver Gestión de Placas',           N'Gestión de Placas', N'/gestion-placas',            NULL),
    ('ventas.resumen.ver',               N'Ver Resumen de Ventas',           N'Ventas',         N'/ventas/resumen',               NULL),
    ('ventas.ranking.ver',               N'Ver Ranking de Ventas',           N'Ventas',         N'/ventas/ranking',               NULL),
    ('presupuesto.gastos.ver',           N'Ver Presupuesto de Gastos',       N'P&L',            N'/presupuesto/gastos',           NULL),
    ('admin.seguridad.ver',              N'Ver Administración de Seguridad', N'Administración', N'/admin/seguridad',              NULL),
    -- Acciones (privilegios numéricos del modelo anterior)
    ('plan-hornos.devolucion.devolucion-cocina',    N'Devolución de cocina',           N'Plan de Hornos', N'/plan-hornos/devolucion',    1),
    ('plan-hornos.devolucion.ver-todas',            N'Ver todas las devoluciones',     N'Plan de Hornos', N'/plan-hornos/devolucion',    2),
    ('plan-hornos.devolucion.cerrar-dia-cocina',    N'Cerrar día de cocina',           N'Plan de Hornos', N'/plan-hornos/devolucion',    3),
    ('plan-hornos.devolucion.cerrar-dia-panaderia', N'Cerrar día de panadería',        N'Plan de Hornos', N'/plan-hornos/devolucion',    4),
    ('plan-hornos.pedido-cocina.recepcion-cocina',  N'Recepción de cocina',            N'Plan de Hornos', N'/plan-hornos/pedido-cocina', 1),
    ('plan-hornos.pedido-cocina.enviar-pedido',     N'Enviar pedido de cocina',        N'Plan de Hornos', N'/plan-hornos/pedido-cocina', 2),
    ('reportes.ver-todas-tiendas',                  N'Ver reportes de todas las tiendas', N'Reportes',    N'/reportes',                  1);

-- submenu NULL = directo bajo el menú; permiso_ver NULL = agrupador
DECLARE @modulos TABLE (
    path        NVARCHAR(200) PRIMARY KEY,
    menu        NVARCHAR(150) NOT NULL,
    submenu     NVARCHAR(150) NULL,
    nombre      NVARCHAR(150) NOT NULL,
    permiso_ver VARCHAR(150)  NULL,
    orden       INT           NOT NULL
);
INSERT INTO @modulos (path, menu, submenu, nombre, permiso_ver, orden) VALUES
    (N'/plan-hornos',        N'Operaciones',       N'Producción', N'Plan de Hornos',        NULL,                     1),
    (N'/reportes',           N'Reportes',          NULL,          N'Reportes',              'reportes.ver',           1),
    (N'/gestion-placas',     N'Gestión de Placas', NULL,          N'Gestión de Placas',     'gestion-placas.ver',     1),
    (N'/ventas/resumen',     N'Ventas',            NULL,          N'Resumen de Ventas',     'ventas.resumen.ver',     1),
    (N'/ventas/ranking',     N'Ventas',            NULL,          N'Ranking de Ventas',     'ventas.ranking.ver',     2),
    (N'/presupuesto/gastos', N'P&L',               NULL,          N'Presupuesto de Gastos', 'presupuesto.gastos.ver', 1),
    (N'/admin/seguridad',    N'Administración',    NULL,          N'Seguridad',             'admin.seguridad.ver',    1);

DECLARE @submodulos TABLE (
    path        NVARCHAR(200) PRIMARY KEY,
    modulo_path NVARCHAR(200) NOT NULL,
    nombre      NVARCHAR(150) NOT NULL,
    permiso_ver VARCHAR(150)  NOT NULL,
    orden       INT           NOT NULL
);
INSERT INTO @submodulos (path, modulo_path, nombre, permiso_ver, orden) VALUES
    (N'/plan-hornos/aph',              N'/plan-hornos', N'Plan de Hornos',             'plan-hornos.aph.ver',              1),
    (N'/plan-hornos/pedido-cocina',    N'/plan-hornos', N'Pedido Cocina',              'plan-hornos.pedido-cocina.ver',    2),
    (N'/plan-hornos/proceso-hornos',   N'/plan-hornos', N'Proceso de Hornos',          'plan-hornos.proceso-hornos.ver',   3),
    (N'/plan-hornos/auxiliar',         N'/plan-hornos', N'Recepción de Horneado',      'plan-hornos.auxiliar.ver',         4),
    (N'/plan-hornos/formato-rotacion', N'/plan-hornos', N'Control de Repostería',      'plan-hornos.formato-rotacion.ver', 5),
    (N'/plan-hornos/devolucion',       N'/plan-hornos', N'Devolución',                 'plan-hornos.devolucion.ver',       6),
    (N'/plan-hornos/motor-calculo',    N'/plan-hornos', N'Motor de Cálculo',           'plan-hornos.motor-calculo.ver',    7),
    (N'/plan-hornos/control',          N'/plan-hornos', N'Control',                    'plan-hornos.control.ver',          8),
    (N'/plan-hornos/parametrizacion',  N'/plan-hornos', N'Parametrización de Tiendas', 'plan-hornos.parametrizacion.ver',  9);

-- Aviso: paths/privilegios del catálogo que no existen en el modelo anterior (no detiene el script)
SELECT 'AVISO - path no existe en sct.seg_mod_modulo' AS aviso, p.path
FROM (SELECT DISTINCT path FROM @permisos) p
WHERE NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo m WHERE m.mod_path = p.path);

SELECT 'AVISO - privilegio no existe en sct.seg_pri_privilegios' AS aviso, p.path, p.pri_anterior, p.clave
FROM @permisos p
WHERE p.pri_anterior IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sct.seg_pri_privilegios pri
                  JOIN sct.seg_mod_modulo m ON m.mod_codigo = pri.pri_codigo_mod
                  WHERE m.mod_path = p.path AND pri.pri_codigo = p.pri_anterior);

-- ─── Carga ───────────────────────────────────────────────────────────────────

BEGIN TRAN;

    -- Menús
    INSERT INTO seg.nav_mnu_menu (mnu_nombre, mnu_descripcion, mnu_orden, mnu_estado, mnu_created_by, mnu_updated_by)
    SELECT m.nombre, m.descripcion, m.orden, 1, @usuarioScript, @usuarioScript
    FROM @menus m
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mnu_menu x WHERE x.mnu_nombre = m.nombre);

    -- Submenús
    INSERT INTO seg.nav_smn_submenu (smn_codigo_mnu, smn_nombre, smn_orden, smn_estado, smn_created_by, smn_updated_by)
    SELECT mn.mnu_codigo, s.nombre, s.orden, 1, @usuarioScript, @usuarioScript
    FROM @submenus s
    JOIN seg.nav_mnu_menu mn ON mn.mnu_nombre = s.menu
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_smn_submenu x WHERE x.smn_codigo_mnu = mn.mnu_codigo AND x.smn_nombre = s.nombre);

    -- Permisos
    INSERT INTO seg.acc_per_permiso (per_clave, per_nombre, per_grupo, per_estado, per_created_by, per_updated_by)
    SELECT p.clave, p.nombre, p.grupo, 1, @usuarioScript, @usuarioScript
    FROM @permisos p
    WHERE NOT EXISTS (SELECT 1 FROM seg.acc_per_permiso x WHERE x.per_clave = p.clave);

    -- Equivalencias con el modelo anterior
    INSERT INTO seg.acc_peq_permiso_equivalencia (peq_mod_path, peq_codigo_pri_anterior, peq_codigo_per)
    SELECT p.path, p.pri_anterior, per.per_codigo
    FROM @permisos p
    JOIN seg.acc_per_permiso per ON per.per_clave = p.clave
    WHERE NOT EXISTS (SELECT 1 FROM seg.acc_peq_permiso_equivalencia x
                      WHERE x.peq_mod_path = p.path
                        AND (x.peq_codigo_pri_anterior = p.pri_anterior
                             OR (x.peq_codigo_pri_anterior IS NULL AND p.pri_anterior IS NULL)));

    -- Módulos
    INSERT INTO seg.nav_mod_modulo
        (mod_codigo_mnu, mod_codigo_smn, mod_codigo_per_ver, mod_nombre, mod_path, mod_orden, mod_estado, mod_created_by, mod_updated_by)
    SELECT mn.mnu_codigo, sm.smn_codigo, per.per_codigo, m.nombre, m.path, m.orden, 1, @usuarioScript, @usuarioScript
    FROM @modulos m
    JOIN seg.nav_mnu_menu mn           ON mn.mnu_nombre = m.menu
    LEFT JOIN seg.nav_smn_submenu sm   ON sm.smn_codigo_mnu = mn.mnu_codigo AND sm.smn_nombre = m.submenu
    LEFT JOIN seg.acc_per_permiso per  ON per.per_clave = m.permiso_ver
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo x WHERE x.mod_path = m.path);

    -- Submódulos
    INSERT INTO seg.nav_smo_submodulo
        (smo_codigo_mod, smo_codigo_per_ver, smo_nombre, smo_path, smo_orden, smo_estado, smo_created_by, smo_updated_by)
    SELECT mo.mod_codigo, per.per_codigo, s.nombre, s.path, s.orden, 1, @usuarioScript, @usuarioScript
    FROM @submodulos s
    JOIN seg.nav_mod_modulo mo   ON mo.mod_path = s.modulo_path
    JOIN seg.acc_per_permiso per ON per.per_clave = s.permiso_ver
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_smo_submodulo x WHERE x.smo_path = s.path);

    -- ─── Verificación ────────────────────────────────────────────────────────

    -- Conteos esperados: 6 menús, 1 submenú, 7 módulos, 9 submódulos, 22 permisos, 22 equivalencias
    SELECT 'DESPUES' AS momento,
           (SELECT COUNT(*) FROM seg.nav_mnu_menu)                 AS menus,
           (SELECT COUNT(*) FROM seg.nav_smn_submenu)              AS submenus,
           (SELECT COUNT(*) FROM seg.nav_mod_modulo)               AS modulos,
           (SELECT COUNT(*) FROM seg.nav_smo_submodulo)            AS submodulos,
           (SELECT COUNT(*) FROM seg.acc_per_permiso)              AS permisos,
           (SELECT COUNT(*) FROM seg.acc_peq_permiso_equivalencia) AS equivalencias;

    -- Árbol de navegación resultante
    SELECT 'DESPUES' AS momento,
           mn.mnu_orden, mn.mnu_nombre AS menu,
           sm.smn_nombre AS submenu,
           mo.mod_nombre AS modulo,
           so.smo_nombre AS submodulo,
           COALESCE(so.smo_path, mo.mod_path) AS path,
           COALESCE(ps.per_clave, pm.per_clave, '(agrupador)') AS permiso_ver
    FROM seg.nav_mod_modulo mo
    JOIN seg.nav_mnu_menu mn          ON mn.mnu_codigo = mo.mod_codigo_mnu
    LEFT JOIN seg.nav_smn_submenu sm  ON sm.smn_codigo = mo.mod_codigo_smn
    LEFT JOIN seg.nav_smo_submodulo so ON so.smo_codigo_mod = mo.mod_codigo
    LEFT JOIN seg.acc_per_permiso pm  ON pm.per_codigo = mo.mod_codigo_per_ver
    LEFT JOIN seg.acc_per_permiso ps  ON ps.per_codigo = so.smo_codigo_per_ver
    ORDER BY mn.mnu_orden, sm.smn_orden, mo.mod_orden, so.smo_orden;

    -- Permisos y su origen en el modelo anterior
    SELECT 'DESPUES' AS momento, per.per_grupo, per.per_clave, per.per_nombre,
           peq.peq_mod_path AS path_anterior, peq.peq_codigo_pri_anterior AS privilegio_anterior
    FROM seg.acc_per_permiso per
    LEFT JOIN seg.acc_peq_permiso_equivalencia peq ON peq.peq_codigo_per = per.per_codigo
    ORDER BY per.per_grupo, per.per_clave;

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
-- COMMIT;
-- ROLLBACK;
