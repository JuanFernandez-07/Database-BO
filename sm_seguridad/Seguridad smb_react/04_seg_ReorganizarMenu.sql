-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███          (4 de 4)
-- Seguridad y navegación propias de smb_react — ESTRUCTURA FINAL DEL MENÚ
-- ════════════════════════════════════════════════════════════════════════════════════
-- Requiere 01, 02 y 03 confirmados. Solo toca el esquema seg (navegación); no cambia permisos,
-- roles ni asignaciones: cada pantalla conserva su permiso "ver", solo cambia de lugar.
--
-- Resultado:
--   Operaciones     (cog-6-tooth)               Producción (wrench-screwdriver) › Plan de Hornos · Gestión de Placas (directo)
--   Comercial       (briefcase)                 Ventas (shopping-cart) › Resumen de Ventas, Ranking de Ventas
--   Finanzas        (banknotes)                 P&L (calculator) › Presupuesto de Gastos
--   Capital Humano  (user-group)                (vacío)
--   Auditoría       (clipboard-document-check)  (vacío)
--   Administración  (shield-check)              Seguridad (directo)
--   Reportes        (document-chart-bar)        Reportes (directo)
-- Los menús vacíos no aparecen en el sidebar hasta que tengan alguna pantalla.
-- Los menús del catálogo inicial que quedan vacíos (Gestión de Placas, Ventas, P&L) se eliminan.
-- El ícono es la clave de src/config/iconosNavegacion.ts de smb_react.
--
-- Idempotente. Transacción sin COMMIT automático.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

IF OBJECT_ID(N'seg.nav_mnu_menu', N'U') IS NULL
    THROW 50080, 'No existe la estructura del esquema seg. Correr 01, 02 y 03 primero.', 1;

DECLARE @usuarioScript VARCHAR(100) = 'SCRIPT';

DECLARE @menus TABLE (nombre NVARCHAR(150) PRIMARY KEY, icono NVARCHAR(100) NOT NULL, orden INT NOT NULL);
INSERT INTO @menus (nombre, icono, orden) VALUES
    (N'Operaciones',    N'cog-6-tooth',              1),
    (N'Comercial',      N'briefcase',                2),
    (N'Finanzas',       N'banknotes',                3),
    (N'Capital Humano', N'user-group',               4),
    (N'Auditoría',      N'clipboard-document-check', 5),
    (N'Administración', N'shield-check',             6),
    (N'Reportes',       N'document-chart-bar',       7);

DECLARE @submenus TABLE (menu NVARCHAR(150), nombre NVARCHAR(150), icono NVARCHAR(100) NOT NULL, orden INT NOT NULL, PRIMARY KEY (menu, nombre));
INSERT INTO @submenus (menu, nombre, icono, orden) VALUES
    (N'Operaciones', N'Producción', N'wrench-screwdriver', 1),
    (N'Comercial',   N'Ventas',     N'shopping-cart',      1),
    (N'Finanzas',    N'P&L',        N'calculator',         1);

-- Ubicación final de cada módulo (por path). submenu NULL = directo bajo el menú.
DECLARE @ubicacion TABLE (path NVARCHAR(200) PRIMARY KEY, menu NVARCHAR(150) NOT NULL, submenu NVARCHAR(150) NULL, orden INT NOT NULL);
INSERT INTO @ubicacion (path, menu, submenu, orden) VALUES
    (N'/plan-hornos',        N'Operaciones',    N'Producción', 1),
    (N'/gestion-placas',     N'Operaciones',    NULL,          1),
    (N'/ventas/resumen',     N'Comercial',      N'Ventas',     1),
    (N'/ventas/ranking',     N'Comercial',      N'Ventas',     2),
    (N'/presupuesto/gastos', N'Finanzas',       N'P&L',        1),
    (N'/admin/seguridad',    N'Administración', NULL,          1),
    (N'/reportes',           N'Reportes',       NULL,          1);

-- Ícono de cada pantalla (clave de src/config/iconosNavegacion.ts). Solo se asigna si no tiene uno:
-- lo que ya se haya elegido desde Administración → Seguridad no se sobrescribe.
DECLARE @iconos TABLE (path NVARCHAR(200) PRIMARY KEY, icono NVARCHAR(100) NOT NULL);
INSERT INTO @iconos (path, icono) VALUES
    -- Módulos
    (N'/plan-hornos',                  N'fire'),
    (N'/gestion-placas',               N'truck'),
    (N'/ventas/resumen',               N'banknotes'),
    (N'/ventas/ranking',               N'trophy'),
    (N'/presupuesto/gastos',           N'calculator'),
    (N'/admin/seguridad',              N'lock-closed'),
    (N'/reportes',                     N'document-chart-bar'),
    -- Submódulos de Plan de Hornos
    (N'/plan-hornos/aph',              N'clipboard-document-list'),
    (N'/plan-hornos/pedido-cocina',    N'shopping-cart'),
    (N'/plan-hornos/proceso-hornos',   N'fire'),
    (N'/plan-hornos/auxiliar',         N'archive-box'),
    (N'/plan-hornos/formato-rotacion', N'arrow-path'),
    (N'/plan-hornos/devolucion',       N'arrow-uturn-left'),
    (N'/plan-hornos/motor-calculo',    N'cpu-chip'),
    (N'/plan-hornos/control',          N'chart-bar'),
    (N'/plan-hornos/parametrizacion',  N'cog-6-tooth');

-- Aviso: módulos esperados que no existen (no detiene el script)
SELECT 'AVISO - módulo no encontrado' AS aviso, u.path
FROM @ubicacion u
WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo m WHERE m.mod_path = u.path);

BEGIN TRAN;

    -- 1. Menús: crear los que faltan y fijar ícono y orden
    INSERT INTO seg.nav_mnu_menu (mnu_nombre, mnu_icono, mnu_orden, mnu_estado, mnu_created_by, mnu_updated_by)
    SELECT m.nombre, m.icono, m.orden, 1, @usuarioScript, @usuarioScript
    FROM @menus m
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mnu_menu x WHERE x.mnu_nombre = m.nombre);

    UPDATE x
    SET x.mnu_icono = m.icono, x.mnu_orden = m.orden, x.mnu_updated_by = @usuarioScript, x.mnu_updated_at = GETDATE()
    FROM seg.nav_mnu_menu x
    JOIN @menus m ON m.nombre = x.mnu_nombre
    WHERE ISNULL(x.mnu_icono, N'') <> m.icono OR x.mnu_orden <> m.orden;

    -- 2. Submenús: crear los que faltan y fijar ícono y orden
    INSERT INTO seg.nav_smn_submenu (smn_codigo_mnu, smn_nombre, smn_icono, smn_orden, smn_estado, smn_created_by, smn_updated_by)
    SELECT mn.mnu_codigo, s.nombre, s.icono, s.orden, 1, @usuarioScript, @usuarioScript
    FROM @submenus s
    JOIN seg.nav_mnu_menu mn ON mn.mnu_nombre = s.menu
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_smn_submenu x WHERE x.smn_codigo_mnu = mn.mnu_codigo AND x.smn_nombre = s.nombre);

    UPDATE x
    SET x.smn_icono = s.icono, x.smn_orden = s.orden, x.smn_updated_by = @usuarioScript, x.smn_updated_at = GETDATE()
    FROM seg.nav_smn_submenu x
    JOIN seg.nav_mnu_menu mn ON mn.mnu_codigo = x.smn_codigo_mnu
    JOIN @submenus s         ON s.menu = mn.mnu_nombre AND s.nombre = x.smn_nombre
    WHERE ISNULL(x.smn_icono, N'') <> s.icono OR x.smn_orden <> s.orden;

    -- 3. Módulos a su lugar final (menú y submenú van juntos: FK compuesta)
    UPDATE mo
    SET mo.mod_codigo_mnu = mn.mnu_codigo,
        mo.mod_codigo_smn = sm.smn_codigo,
        mo.mod_orden      = u.orden,
        mo.mod_updated_by = @usuarioScript,
        mo.mod_updated_at = GETDATE()
    FROM seg.nav_mod_modulo mo
    JOIN @ubicacion u              ON u.path = mo.mod_path
    JOIN seg.nav_mnu_menu mn       ON mn.mnu_nombre = u.menu
    LEFT JOIN seg.nav_smn_submenu sm ON sm.smn_codigo_mnu = mn.mnu_codigo AND sm.smn_nombre = u.submenu
    WHERE mo.mod_codigo_mnu <> mn.mnu_codigo
       OR ISNULL(mo.mod_codigo_smn, -1) <> ISNULL(sm.smn_codigo, -1)
       OR mo.mod_orden <> u.orden;

    -- 3b. Íconos de módulos y submódulos que aún no tienen uno
    UPDATE mo
    SET mo.mod_icono = i.icono, mo.mod_updated_by = @usuarioScript, mo.mod_updated_at = GETDATE()
    FROM seg.nav_mod_modulo mo
    JOIN @iconos i ON i.path = mo.mod_path
    WHERE mo.mod_icono IS NULL OR mo.mod_icono = N'';

    UPDATE so
    SET so.smo_icono = i.icono, so.smo_updated_by = @usuarioScript, so.smo_updated_at = GETDATE()
    FROM seg.nav_smo_submodulo so
    JOIN @iconos i ON i.path = so.smo_path
    WHERE so.smo_icono IS NULL OR so.smo_icono = N'';

    -- 4. Menús que ya no están en la estructura final y quedaron vacíos
    DELETE x
    FROM seg.nav_mnu_menu x
    WHERE NOT EXISTS (SELECT 1 FROM @menus m WHERE m.nombre = x.mnu_nombre)
      AND NOT EXISTS (SELECT 1 FROM seg.nav_smn_submenu s WHERE s.smn_codigo_mnu = x.mnu_codigo)
      AND NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo mo WHERE mo.mod_codigo_mnu = x.mnu_codigo);

    -- ─── Verificación ────────────────────────────────────────────────────────

    -- Menús que no se pudieron borrar porque aún tienen contenido (debe salir vacío)
    SELECT 'DESPUES - debe salir vacío' AS momento, x.mnu_codigo, x.mnu_nombre
    FROM seg.nav_mnu_menu x
    WHERE NOT EXISTS (SELECT 1 FROM @menus m WHERE m.nombre = x.mnu_nombre);

    -- Menús finales
    SELECT 'DESPUES' AS momento, mnu_orden, mnu_nombre, mnu_icono, mnu_estado
    FROM seg.nav_mnu_menu
    ORDER BY mnu_orden;

    -- Árbol final
    SELECT 'DESPUES' AS momento,
           mn.mnu_orden, mn.mnu_nombre AS menu,
           sm.smn_nombre AS submenu,
           mo.mod_nombre AS modulo,
           so.smo_nombre AS submodulo,
           COALESCE(so.smo_path, mo.mod_path) AS path,
           COALESCE(so.smo_icono, mo.mod_icono) AS icono
    FROM seg.nav_mnu_menu mn
    LEFT JOIN seg.nav_mod_modulo mo     ON mo.mod_codigo_mnu = mn.mnu_codigo
    LEFT JOIN seg.nav_smn_submenu sm    ON sm.smn_codigo = mo.mod_codigo_smn
    LEFT JOIN seg.nav_smo_submodulo so  ON so.smo_codigo_mod = mo.mod_codigo
    ORDER BY mn.mnu_orden, sm.smn_orden, mo.mod_orden, so.smo_orden;

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
 COMMIT;
-- ROLLBACK;
