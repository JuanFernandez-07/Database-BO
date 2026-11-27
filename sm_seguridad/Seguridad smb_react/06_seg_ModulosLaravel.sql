-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███
-- Seguridad y navegación propias de smb_react — PANTALLAS DE LARAVEL EMBEBIDAS
-- ════════════════════════════════════════════════════════════════════════════════════
-- Requiere 01 a 05 confirmados. Agrega al menú de smb_react las pantallas de smb-laravel
-- que se siguen usando, para abrirlas dentro de smb_react (iframe):
--
--   NÓMINA        (todas sus pantallas)        → Capital Humano › Nómina
--   INVENTARIO    (todas sus pantallas)        → Operaciones › Inventario
--   FINANZAS      (solo /finanzas/proyeccion_ventas) → Finanzas (directo)
--   CONTABILIDAD  (solo estas, por nombre)     → Comercial › Ventas
--                    Lectura de Cajas            (pantalla)
--                    Cierre                      (agrupador, sin pantalla propia)
--                      ├ Cuadre de Delivery
--                      ├ Corte de Caja
--                      └ Cierre de Día
--   Las demás pantallas de CONTABILIDAD (hoy solo existen en dev) se agregan como módulos
--   de Comercial › Ventas después de Cierre, y se listan en un aviso para ubicarlas luego.
--
-- Por cada pantalla de Laravel (leída de sct, SOLO LECTURA):
--   - Pantalla en seg (módulo o submódulo) con path  /laravel + mod_path  (ej. /laravel/nomina/horas_extras)
--   - Permiso "ver" derivado del path                laravel.nomina.horas_extras.ver
--   - Equivalencia sct → seg para que 03_seg_Migracion asigne el permiso a los roles
--     que hoy tienen la pantalla en Laravel.
--
-- DESPUÉS de confirmar este script: volver a correr 03_seg_Migracion.sql y luego 05
-- para que los roles y usuarios de estas pantallas queden migrados.
--
-- No modifica nada del esquema sct. Idempotente. Transacción sin COMMIT automático.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

IF OBJECT_ID(N'seg.nav_mnu_menu', N'U') IS NULL
    THROW 50090, 'No existe la estructura del esquema seg. Correr 01 a 05 primero.', 1;

DECLARE @usuarioScript VARCHAR(100) = 'SCRIPT';
DECLARE @prefijoReact  NVARCHAR(20) = N'/laravel';   -- igual a PREFIJO_PATH_LARAVEL (smb_react) y PrefijoPathReact (smb_net)

-- ─── 1. Menús completos de Laravel (todas sus pantallas como módulos) ─────────
-- menu_sct = nombre exacto de sct.seg_mnu_menu; path_sct limita a una sola pantalla de ese menú.
-- submenu NULL = directo bajo el menú. Íconos: claves de src/config/iconosNavegacion.ts.
DECLARE @reglas TABLE (
    regla          INT           PRIMARY KEY,
    menu_sct       NVARCHAR(150) NOT NULL,
    path_sct       NVARCHAR(200) NULL,
    menu           NVARCHAR(150) NOT NULL,
    submenu        NVARCHAR(150) NULL,
    icono_submenu  NVARCHAR(100) NULL,
    orden_submenu  INT           NULL,
    icono_modulo   NVARCHAR(100) NOT NULL
);
INSERT INTO @reglas VALUES
    (1, N'NÓMINA',     NULL,                  N'Capital Humano', N'Nómina',     N'identification', 1,    N'clock'),
    (2, N'INVENTARIO', NULL,                  N'Operaciones',    N'Inventario', N'archive-box',    2,    N'cube'),
    (3, N'FINANZAS',   N'/finanzas/proyeccion_ventas', N'Finanzas', NULL,         NULL,              NULL, N'presentation-chart-line');

-- ─── 2. CONTABILIDAD: pantallas puntuales, por nombre, a Comercial › Ventas ───
-- padre NULL = módulo directo en el submenú; padre = nombre del agrupador del que cuelga como submódulo.
DECLARE @menuVentas    NVARCHAR(150) = N'Comercial';
DECLARE @submenuVentas NVARCHAR(150) = N'Ventas';
DECLARE @agrupadores TABLE (nombre NVARCHAR(150) PRIMARY KEY, icono NVARCHAR(100) NOT NULL, orden INT NOT NULL);
INSERT INTO @agrupadores VALUES
    (N'Cierre', N'lock-closed', 4);

DECLARE @contabilidad TABLE (nombre_sct NVARCHAR(150) PRIMARY KEY, padre NVARCHAR(150) NULL, icono NVARCHAR(100) NOT NULL, orden INT NOT NULL);
INSERT INTO @contabilidad VALUES
    (N'Lectura de Cajas',   NULL,      N'computer-desktop', 3),   -- después de Resumen (1) y Ranking (2)
    (N'Cuadre de Delivery', N'Cierre', N'truck',            1),
    (N'Corte de Caja',      N'Cierre', N'banknotes',        2),
    (N'Cierre de Día',      N'Cierre', N'calendar-days',    3);

-- ─── Pantallas de Laravel elegidas (lectura de sct) ─────────────────────────
-- tipo M = módulo con pantalla; S = submódulo de un agrupador
CREATE TABLE #laravel (
    path_sct  NVARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    nombre    NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,
    tipo      CHAR(1)       NOT NULL,
    menu      NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,
    submenu   NVARCHAR(150) COLLATE DATABASE_DEFAULT NULL,
    padre     NVARCHAR(150) COLLATE DATABASE_DEFAULT NULL,
    icono     NVARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL,
    orden     INT           NOT NULL
);

-- Pantallas activas y visibles de Laravel, con el mismo formato de path que validan smb_net y Laravel
-- (/letras-numeros_y/barras, sin // ni / final)
CREATE TABLE #sct (
    menu_sct   NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,
    mod_nombre NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,
    mod_path   NVARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
    mod_orden  INT           NOT NULL,
    path_ok    BIT           NOT NULL
);
INSERT INTO #sct (menu_sct, mod_nombre, mod_path, mod_orden, path_ok)
SELECT mn.mnu_nombre, mo.mod_nombre, mo.mod_path, ISNULL(mo.mod_orden, 0),
       CASE WHEN mo.mod_path LIKE N'/%'
             AND mo.mod_path NOT LIKE N'%[^A-Za-z0-9/_-]%'
             AND mo.mod_path NOT LIKE N'%//%'
             AND mo.mod_path NOT LIKE N'%/' THEN 1 ELSE 0 END
FROM sct.seg_mod_modulo mo
JOIN sct.seg_mnu_menu mn ON mn.mnu_codigo = mo.mod_mnu_codigo
WHERE mo.mod_estado = 1 AND mo.mod_visible = 1 AND mo.mod_path IS NOT NULL
  AND mn.mnu_nombre IN (SELECT menu_sct FROM @reglas UNION SELECT N'CONTABILIDAD');

-- Menús completos
INSERT INTO #laravel (path_sct, nombre, tipo, menu, submenu, padre, icono, orden)
SELECT s.mod_path, MIN(s.mod_nombre), 'M', r.menu, r.submenu, NULL, r.icono_modulo,
       ROW_NUMBER() OVER (PARTITION BY r.regla ORDER BY MIN(s.mod_orden), MIN(s.mod_nombre))
FROM #sct s
JOIN @reglas r ON r.menu_sct = s.menu_sct AND (r.path_sct IS NULL OR r.path_sct = s.mod_path)
WHERE s.path_ok = 1
GROUP BY s.mod_path, r.regla, r.menu, r.submenu, r.icono_modulo;

-- Contabilidad (por nombre); si el mismo path ya entró por otra regla, no se repite
INSERT INTO #laravel (path_sct, nombre, tipo, menu, submenu, padre, icono, orden)
SELECT s.mod_path, c.nombre_sct, CASE WHEN c.padre IS NULL THEN 'M' ELSE 'S' END,
       @menuVentas, @submenuVentas, c.padre, c.icono, c.orden
FROM @contabilidad c
JOIN #sct s ON s.menu_sct = N'CONTABILIDAD' AND s.mod_nombre = c.nombre_sct AND s.path_ok = 1
WHERE NOT EXISTS (SELECT 1 FROM #laravel l WHERE l.path_sct = s.mod_path);

-- Resto de CONTABILIDAD: módulos de Comercial › Ventas después de Cierre (orden 5 en adelante)
INSERT INTO #laravel (path_sct, nombre, tipo, menu, submenu, padre, icono, orden)
SELECT s.mod_path, MIN(s.mod_nombre), 'M', @menuVentas, @submenuVentas, NULL, N'document-text',
       4 + ROW_NUMBER() OVER (ORDER BY MIN(s.mod_orden), MIN(s.mod_nombre))
FROM #sct s
WHERE s.menu_sct = N'CONTABILIDAD' AND s.path_ok = 1
  AND NOT EXISTS (SELECT 1 FROM @contabilidad c WHERE c.nombre_sct = s.mod_nombre)
  AND NOT EXISTS (SELECT 1 FROM #laravel l WHERE l.path_sct = s.mod_path)
GROUP BY s.mod_path;

-- ─── Avisos (no detienen el script) ──────────────────────────────────────────
SELECT 'AVISO - regla sin pantallas en Laravel' AS aviso, r.menu_sct, r.path_sct
FROM @reglas r
WHERE NOT EXISTS (SELECT 1 FROM #laravel l WHERE l.menu = r.menu AND ISNULL(l.submenu, N'') = ISNULL(r.submenu, N'') AND l.padre IS NULL AND l.icono = r.icono_modulo);

SELECT 'AVISO - pantalla de CONTABILIDAD esperada que no existe en esta base' AS aviso, c.nombre_sct
FROM @contabilidad c
WHERE NOT EXISTS (SELECT 1 FROM #sct s WHERE s.menu_sct = N'CONTABILIDAD' AND s.mod_nombre = c.nombre_sct);

SELECT 'AVISO - pantalla de CONTABILIDAD fuera de la estructura (se agrega como módulo de Ventas)' AS aviso, s.mod_nombre, s.mod_path
FROM #sct s
WHERE s.menu_sct = N'CONTABILIDAD'
  AND NOT EXISTS (SELECT 1 FROM @contabilidad c WHERE c.nombre_sct = s.mod_nombre);

SELECT 'AVISO - path con formato no soportado (no se agrega)' AS aviso, s.menu_sct, s.mod_nombre, s.mod_path
FROM #sct s
WHERE s.path_ok = 0
  AND (EXISTS (SELECT 1 FROM @reglas r WHERE r.menu_sct = s.menu_sct AND (r.path_sct IS NULL OR r.path_sct = s.mod_path))
       OR EXISTS (SELECT 1 FROM @contabilidad c WHERE s.menu_sct = N'CONTABILIDAD' AND c.nombre_sct = s.mod_nombre));

-- Lo que se va a agregar
SELECT 'ANTES - pantallas de Laravel a agregar' AS momento, l.menu, l.submenu, l.padre AS agrupador,
       l.nombre, l.tipo, l.path_sct, @prefijoReact + l.path_sct AS path_react,
       'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver' AS permiso
FROM #laravel l
ORDER BY l.menu, l.submenu, l.padre, l.orden;

BEGIN TRAN;

    -- 1. Menús (ya existen desde 04; se crean solo si faltan)
    INSERT INTO seg.nav_mnu_menu (mnu_nombre, mnu_orden, mnu_estado, mnu_created_by, mnu_updated_by)
    SELECT DISTINCT l.menu, 99, 1, @usuarioScript, @usuarioScript
    FROM #laravel l
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mnu_menu x WHERE x.mnu_nombre = l.menu);

    -- 2. Submenús (Nómina, Inventario; Ventas ya existe desde 04)
    INSERT INTO seg.nav_smn_submenu (smn_codigo_mnu, smn_nombre, smn_icono, smn_orden, smn_estado, smn_created_by, smn_updated_by)
    SELECT mn.mnu_codigo, d.submenu, d.icono, d.orden, 1, @usuarioScript, @usuarioScript
    FROM (SELECT DISTINCT l.menu, l.submenu,
                 COALESCE(r.icono_submenu, N'shopping-cart') AS icono, COALESCE(r.orden_submenu, 1) AS orden
          FROM #laravel l
          LEFT JOIN @reglas r ON r.menu = l.menu AND r.submenu = l.submenu
          WHERE l.submenu IS NOT NULL) d
    JOIN seg.nav_mnu_menu mn ON mn.mnu_nombre = d.menu
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_smn_submenu x WHERE x.smn_codigo_mnu = mn.mnu_codigo AND x.smn_nombre = d.submenu);

    -- 3. Permiso "ver" de cada pantalla
    INSERT INTO seg.acc_per_permiso (per_clave, per_nombre, per_grupo, per_estado, per_created_by, per_updated_by)
    SELECT 'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver',
           N'Ver ' + l.nombre,
           COALESCE(l.padre, l.submenu, l.menu),
           1, @usuarioScript, @usuarioScript
    FROM #laravel l
    WHERE NOT EXISTS (SELECT 1 FROM seg.acc_per_permiso x
                      WHERE x.per_clave = 'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver');

    -- 4. Módulos con pantalla (solo los que aún no existen: lo editado desde Administración no se pisa)
    INSERT INTO seg.nav_mod_modulo (mod_codigo_mnu, mod_codigo_smn, mod_codigo_per_ver, mod_nombre, mod_path,
                                    mod_icono, mod_orden, mod_estado, mod_created_by, mod_updated_by)
    SELECT mn.mnu_codigo, sm.smn_codigo, per.per_codigo, l.nombre, @prefijoReact + l.path_sct,
           l.icono, l.orden, 1, @usuarioScript, @usuarioScript
    FROM #laravel l
    JOIN seg.nav_mnu_menu mn         ON mn.mnu_nombre = l.menu
    LEFT JOIN seg.nav_smn_submenu sm ON sm.smn_codigo_mnu = mn.mnu_codigo AND sm.smn_nombre = l.submenu
    JOIN seg.acc_per_permiso per     ON per.per_clave = 'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver'
    WHERE l.tipo = 'M'
      AND NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo x WHERE x.mod_path = @prefijoReact + l.path_sct);

    -- 5. Agrupadores (sin pantalla ni permiso propio: se ven si algún submódulo se ve)
    INSERT INTO seg.nav_mod_modulo (mod_codigo_mnu, mod_codigo_smn, mod_codigo_per_ver, mod_nombre, mod_path,
                                    mod_icono, mod_orden, mod_estado, mod_created_by, mod_updated_by)
    SELECT mn.mnu_codigo, sm.smn_codigo, NULL, a.nombre, NULL, a.icono, a.orden, 1, @usuarioScript, @usuarioScript
    FROM @agrupadores a
    JOIN seg.nav_mnu_menu mn    ON mn.mnu_nombre = @menuVentas
    JOIN seg.nav_smn_submenu sm ON sm.smn_codigo_mnu = mn.mnu_codigo AND sm.smn_nombre = @submenuVentas
    WHERE EXISTS (SELECT 1 FROM #laravel l WHERE l.padre = a.nombre)
      AND NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo x
                      WHERE x.mod_codigo_smn = sm.smn_codigo AND x.mod_nombre = a.nombre AND x.mod_path IS NULL);

    -- 6. Submódulos dentro de su agrupador
    INSERT INTO seg.nav_smo_submodulo (smo_codigo_mod, smo_codigo_per_ver, smo_nombre, smo_path,
                                       smo_icono, smo_orden, smo_estado, smo_created_by, smo_updated_by)
    SELECT ag.mod_codigo, per.per_codigo, l.nombre, @prefijoReact + l.path_sct,
           l.icono, l.orden, 1, @usuarioScript, @usuarioScript
    FROM #laravel l
    JOIN seg.nav_mnu_menu mn     ON mn.mnu_nombre = l.menu
    JOIN seg.nav_smn_submenu sm  ON sm.smn_codigo_mnu = mn.mnu_codigo AND sm.smn_nombre = l.submenu
    JOIN seg.nav_mod_modulo ag   ON ag.mod_codigo_smn = sm.smn_codigo AND ag.mod_nombre = l.padre AND ag.mod_path IS NULL
    JOIN seg.acc_per_permiso per ON per.per_clave = 'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver'
    WHERE l.tipo = 'S'
      AND NOT EXISTS (SELECT 1 FROM seg.nav_smo_submodulo x WHERE x.smo_path = @prefijoReact + l.path_sct);

    -- 7. Equivalencia sct → seg (la usa 03_seg_Migracion para pasar el acceso de cada rol)
    INSERT INTO seg.acc_peq_permiso_equivalencia (peq_mod_path, peq_codigo_pri_anterior, peq_codigo_per)
    SELECT l.path_sct, NULL, per.per_codigo
    FROM #laravel l
    JOIN seg.acc_per_permiso per ON per.per_clave = 'laravel' + REPLACE(l.path_sct, N'/', N'.') + '.ver'
    WHERE NOT EXISTS (SELECT 1 FROM seg.acc_peq_permiso_equivalencia x
                      WHERE x.peq_mod_path = l.path_sct AND x.peq_codigo_pri_anterior IS NULL);

    -- ─── Verificación ────────────────────────────────────────────────────────

    -- Pantallas elegidas que no quedaron en el menú (debe salir vacío)
    SELECT 'DESPUES - debe salir vacío' AS momento, l.nombre, l.path_sct
    FROM #laravel l
    WHERE NOT EXISTS (SELECT 1 FROM seg.nav_mod_modulo mo WHERE mo.mod_path = @prefijoReact + l.path_sct)
      AND NOT EXISTS (SELECT 1 FROM seg.nav_smo_submodulo so WHERE so.smo_path = @prefijoReact + l.path_sct);

    -- Árbol de las pantallas de Laravel y cuántos roles de sct tienen hoy cada una
    SELECT 'DESPUES' AS momento, mn.mnu_nombre AS menu, sm.smn_nombre AS submenu,
           mo.mod_nombre AS modulo, so.smo_nombre AS submodulo,
           COALESCE(so.smo_path, mo.mod_path) AS path, per.per_clave,
           (SELECT COUNT(DISTINCT CONCAT(rmo.rmo_codigo_neg, '-', rmo.rmo_codigo_rol))
            FROM sct.seg_rmo_rol_modulo rmo
            JOIN sct.seg_mod_modulo smo ON smo.mod_codigo = rmo.rmo_codigo_mod AND smo.mod_mnu_codigo = rmo.rmo_codigo_mnu
            WHERE smo.mod_path = peq.peq_mod_path AND rmo.rmo_estado = 1) AS roles_sct_con_acceso
    FROM seg.nav_mod_modulo mo
    JOIN seg.nav_mnu_menu mn                       ON mn.mnu_codigo = mo.mod_codigo_mnu
    LEFT JOIN seg.nav_smn_submenu sm               ON sm.smn_codigo = mo.mod_codigo_smn
    LEFT JOIN seg.nav_smo_submodulo so             ON so.smo_codigo_mod = mo.mod_codigo
    JOIN seg.acc_per_permiso per                   ON per.per_codigo = COALESCE(so.smo_codigo_per_ver, mo.mod_codigo_per_ver)
    LEFT JOIN seg.acc_peq_permiso_equivalencia peq ON peq.peq_codigo_per = per.per_codigo AND peq.peq_codigo_pri_anterior IS NULL
    WHERE COALESCE(so.smo_path, mo.mod_path) LIKE @prefijoReact + N'/%'
    ORDER BY mn.mnu_orden, sm.smn_orden, mo.mod_orden, so.smo_orden;

-- Revisar los resultados y ejecutar UNA de estas dos líneas.
-- Luego volver a correr 03_seg_Migracion.sql y 05_seg_PermisoEstructuraMenu.sql.
 COMMIT;
-- ROLLBACK;

DROP TABLE IF EXISTS #laravel;
DROP TABLE IF EXISTS #sct;