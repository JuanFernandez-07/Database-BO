-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███
-- Jerarquía de menú para smb_react: Menú → Submenú → Módulo → Submódulo.
-- Ejemplo que se carga: Operaciones → Producción → Plan de Hornos → Plan, Devolución, Control…
-- ════════════════════════════════════════════════════════════════════════════════════
-- Qué hace:
--   1. Índice único nuevo sobre seg_mod_modulo.mod_codigo (la PK es compuesta menú+módulo y las
--      FK nuevas necesitan apuntar solo al módulo). No agrega columnas.
--   2. Tabla nueva sct.seg_smn_submenu: agrupadores dentro de un menú. Solo ordenan; nunca llevan permisos.
--   3. Tabla nueva sct.seg_umo_ubicacion_modulo: dónde va cada módulo. O dentro de un submenú
--      (umo_codigo_smn) o como submódulo de otro módulo (umo_codigo_mod_padre), nunca ambos.
--      Módulo sin fila aquí = directo bajo su menú, como hoy.
--   4. Carga: menú Operaciones, submenú Producción, módulo agrupador Plan de Hornos (/plan-hornos,
--      SIN roles: se muestra si el usuario tiene acceso a alguna de sus pantallas) y la ubicación
--      de las pantallas actuales de /plan-hornos/* como submódulos de Plan de Hornos.
--
-- Qué NO hace (a propósito):
--   - No agrega ni cambia columnas de tablas existentes (smb-laravel las lee).
--   - No toca seg_rmo_rol_modulo, seg_pri_privilegios, SEG_RPR_ROL_PRIVILEGIO, roles ni usuarios.
--   - No cambia mod_mnu_codigo de las pantallas: Laravel sigue agrupándolas como hoy; smb_react usa
--     la ubicación. Para un módulo con fila en seg_umo, su mod_mnu_codigo no se usa en el menú nuevo.
--
-- Reglas que valida smb_net (no caben en un CHECK porque miran otras filas):
--   - El padre de un submódulo debe ser un módulo SIN padre (máximo 4 niveles, sin ciclos).
--   - Un módulo con submódulos no puede pasar a ser submódulo.
--   - No se borra un submenú con módulos ni un módulo con submódulos.
--
-- Idempotente (busca por nombre/path; los códigos se calculan). Corre en una transacción y NO confirma
-- sola: revisar los SELECT de DESPUÉS y ejecutar COMMIT o ROLLBACK al final. No dejar la transacción
-- abierta: bloquea las tablas de seguridad y el login.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

DECLARE @menuNombre    NVARCHAR(200) = N'Operaciones';
DECLARE @submenuNombre NVARCHAR(200) = N'Producción';
DECLARE @moduloNombre  NVARCHAR(200) = N'Plan de Hornos';
DECLARE @moduloPath    NVARCHAR(200) = N'/plan-hornos';

-- Pantallas de Plan de Hornos en el orden del sidebar actual de smb_react
DECLARE @pantallas TABLE (path NVARCHAR(200) PRIMARY KEY, orden INT NOT NULL);
INSERT INTO @pantallas (path, orden) VALUES
    (N'/plan-hornos/aph',              1),
    (N'/plan-hornos/pedido-cocina',    2),
    (N'/plan-hornos/proceso-hornos',   3),
    (N'/plan-hornos/auxiliar',         4),
    (N'/plan-hornos/formato-rotacion', 5),
    (N'/plan-hornos/devolucion',       6),
    (N'/plan-hornos/motor-calculo',    7),
    (N'/plan-hornos/control',          8),
    (N'/plan-hornos/parametrizacion',  9);

-- ─── Validaciones previas (no abren transacción) ──────────────────────────────
-- Códigos de módulo repetidos entre menús impiden el índice único.
IF EXISTS (SELECT 1 FROM sct.seg_mod_modulo GROUP BY mod_codigo HAVING COUNT(*) > 1)
BEGIN
    SELECT mod_codigo, COUNT(*) AS veces,
           STRING_AGG(CONCAT(mod_mnu_codigo, ':', mod_nombre), ' | ') AS detalle
    FROM sct.seg_mod_modulo
    GROUP BY mod_codigo
    HAVING COUNT(*) > 1;
    THROW 50040, 'Hay mod_codigo repetidos en sct.seg_mod_modulo. Resolverlos antes de correr este script.', 1;
END;

-- Pantallas que no existen (se reportan; no detienen el script)
SELECT 'PANTALLA NO ENCONTRADA' AS aviso, p.path
FROM @pantallas p
WHERE NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo m WHERE m.mod_path = p.path);

-- Estado antes
SELECT 'ANTES' AS momento, m.mod_codigo, m.mod_mnu_codigo, mn.mnu_nombre, m.mod_nombre, m.mod_path
FROM sct.seg_mod_modulo m
LEFT JOIN sct.seg_mnu_menu mn ON mn.mnu_codigo = m.mod_mnu_codigo
WHERE m.mod_path LIKE N'/plan-hornos%'
ORDER BY m.mod_path;

BEGIN TRAN;

    -- 1. Índice único sobre mod_codigo
    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID(N'sct.seg_mod_modulo') AND name = N'UX_seg_mod_modulo_codigo')
        CREATE UNIQUE NONCLUSTERED INDEX UX_seg_mod_modulo_codigo ON sct.seg_mod_modulo (mod_codigo);

    -- 2. Tabla de submenús
    IF OBJECT_ID(N'sct.seg_smn_submenu', N'U') IS NULL
        CREATE TABLE sct.seg_smn_submenu (
            smn_codigo      INT IDENTITY(1,1) NOT NULL,
            smn_codigo_mnu  INT               NOT NULL,
            smn_nombre      NVARCHAR(200)     NOT NULL,
            smn_orden       INT               NOT NULL CONSTRAINT DF_seg_smn_submenu_orden      DEFAULT (0),
            smn_estado      BIT               NOT NULL CONSTRAINT DF_seg_smn_submenu_estado     DEFAULT (1),
            smn_created_at  DATETIME          NOT NULL CONSTRAINT DF_seg_smn_submenu_created_at DEFAULT (GETDATE()),
            smn_updated_at  DATETIME          NOT NULL CONSTRAINT DF_seg_smn_submenu_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_seg_smn_submenu PRIMARY KEY CLUSTERED (smn_codigo),
            CONSTRAINT FK_seg_smn_submenu_menu FOREIGN KEY (smn_codigo_mnu)
                REFERENCES sct.seg_mnu_menu (mnu_codigo),
            CONSTRAINT UQ_seg_smn_submenu_menu_nombre UNIQUE (smn_codigo_mnu, smn_nombre)
        );

    -- 3. Tabla de ubicación de módulos
    IF OBJECT_ID(N'sct.seg_umo_ubicacion_modulo', N'U') IS NULL
    BEGIN
        CREATE TABLE sct.seg_umo_ubicacion_modulo (
            umo_codigo_mod        INT      NOT NULL,
            umo_codigo_smn        INT      NULL,
            umo_codigo_mod_padre  INT      NULL,
            umo_orden             INT      NOT NULL CONSTRAINT DF_seg_umo_ubicacion_modulo_orden      DEFAULT (0),
            umo_created_at        DATETIME NOT NULL CONSTRAINT DF_seg_umo_ubicacion_modulo_created_at DEFAULT (GETDATE()),
            umo_updated_at        DATETIME NOT NULL CONSTRAINT DF_seg_umo_ubicacion_modulo_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_seg_umo_ubicacion_modulo PRIMARY KEY CLUSTERED (umo_codigo_mod),
            -- Si se borra el módulo, se va su ubicación
            CONSTRAINT FK_seg_umo_ubicacion_modulo_modulo FOREIGN KEY (umo_codigo_mod)
                REFERENCES sct.seg_mod_modulo (mod_codigo) ON DELETE CASCADE,
            -- No se borra un submenú con módulos
            CONSTRAINT FK_seg_umo_ubicacion_modulo_submenu FOREIGN KEY (umo_codigo_smn)
                REFERENCES sct.seg_smn_submenu (smn_codigo),
            -- No se borra un módulo con submódulos
            CONSTRAINT FK_seg_umo_ubicacion_modulo_padre FOREIGN KEY (umo_codigo_mod_padre)
                REFERENCES sct.seg_mod_modulo (mod_codigo),
            -- Exactamente un destino: submenú o módulo padre
            CONSTRAINT CK_seg_umo_ubicacion_modulo_destino CHECK (
                (umo_codigo_smn IS NOT NULL AND umo_codigo_mod_padre IS NULL)
             OR (umo_codigo_smn IS NULL     AND umo_codigo_mod_padre IS NOT NULL)),
            CONSTRAINT CK_seg_umo_ubicacion_modulo_no_autopadre CHECK (umo_codigo_mod_padre <> umo_codigo_mod)
        );

        CREATE NONCLUSTERED INDEX IX_seg_umo_ubicacion_modulo_smn   ON sct.seg_umo_ubicacion_modulo (umo_codigo_smn);
        CREATE NONCLUSTERED INDEX IX_seg_umo_ubicacion_modulo_padre ON sct.seg_umo_ubicacion_modulo (umo_codigo_mod_padre);
    END;

    -- 4a. Menú Operaciones
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre)
        INSERT INTO sct.seg_mnu_menu (mnu_codigo, mnu_nombre, mnu_descripcion, mnu_estado, mnu_created_at, mnu_updated_at)
        SELECT ISNULL(MAX(mnu_codigo), 0) + 1, @menuNombre, N'Operaciones de tienda y producción', 1, GETDATE(), GETDATE()
        FROM sct.seg_mnu_menu;

    DECLARE @menu INT = (SELECT mnu_codigo FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre);

    -- 4b. Submenú Producción
    IF NOT EXISTS (SELECT 1 FROM sct.seg_smn_submenu WHERE smn_codigo_mnu = @menu AND smn_nombre = @submenuNombre)
        INSERT INTO sct.seg_smn_submenu (smn_codigo_mnu, smn_nombre, smn_orden, smn_estado)
        VALUES (@menu, @submenuNombre, 1, 1);

    DECLARE @submenu INT = (SELECT smn_codigo FROM sct.seg_smn_submenu
                            WHERE smn_codigo_mnu = @menu AND smn_nombre = @submenuNombre);

    -- 4c. Módulo agrupador Plan de Hornos (sin roles)
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo WHERE mod_path = @moduloPath)
    BEGIN
        DECLARE @modNuevo INT = (SELECT ISNULL(MAX(mod_codigo), 0) + 1 FROM sct.seg_mod_modulo);

        INSERT INTO sct.seg_mod_modulo
            (mod_codigo, mod_mnu_codigo, mod_nombre, mod_descripcion, mod_path, mod_estado, mod_orden, mod_visible, mod_created_at, mod_updated_at)
        VALUES
            (@modNuevo, @menu, @moduloNombre, N'Agrupador de las pantallas de Plan de Hornos (sin roles asignados)',
             @moduloPath, '1', CAST(@modNuevo AS VARCHAR(10)), 1, GETDATE(), GETDATE());
    END;

    DECLARE @moduloPlanHornos INT = (SELECT mod_codigo FROM sct.seg_mod_modulo WHERE mod_path = @moduloPath);

    -- 4d. Plan de Hornos dentro de Producción
    IF NOT EXISTS (SELECT 1 FROM sct.seg_umo_ubicacion_modulo WHERE umo_codigo_mod = @moduloPlanHornos)
        INSERT INTO sct.seg_umo_ubicacion_modulo (umo_codigo_mod, umo_codigo_smn, umo_orden)
        VALUES (@moduloPlanHornos, @submenu, 1);

    -- 4e. Pantallas como submódulos de Plan de Hornos
    INSERT INTO sct.seg_umo_ubicacion_modulo (umo_codigo_mod, umo_codigo_mod_padre, umo_orden)
    SELECT m.mod_codigo, @moduloPlanHornos, p.orden
    FROM @pantallas p
    JOIN sct.seg_mod_modulo m ON m.mod_path = p.path
    WHERE NOT EXISTS (SELECT 1 FROM sct.seg_umo_ubicacion_modulo u WHERE u.umo_codigo_mod = m.mod_codigo);

    -- Estado después
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mnu_menu    WHERE mnu_codigo = @menu;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_smn_submenu WHERE smn_codigo = @submenu;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mod_modulo  WHERE mod_codigo = @moduloPlanHornos;

    -- Árbol resultante (lo que armará smb_net)
    SELECT 'DESPUES' AS momento,
           mn.mnu_nombre      AS menu,
           s.smn_nombre       AS submenu,
           mp.mod_nombre      AS modulo,
           m.mod_nombre       AS submodulo,
           m.mod_path,
           u.umo_orden
    FROM sct.seg_umo_ubicacion_modulo u
    JOIN sct.seg_mod_modulo m                   ON m.mod_codigo  = u.umo_codigo_mod
    LEFT JOIN sct.seg_umo_ubicacion_modulo up   ON up.umo_codigo_mod = u.umo_codigo_mod_padre
    LEFT JOIN sct.seg_mod_modulo mp             ON mp.mod_codigo = u.umo_codigo_mod_padre
    LEFT JOIN sct.seg_smn_submenu s             ON s.smn_codigo  = COALESCE(u.umo_codigo_smn, up.umo_codigo_smn)
    LEFT JOIN sct.seg_mnu_menu mn               ON mn.mnu_codigo = s.smn_codigo_mnu
    ORDER BY menu, submenu, modulo, u.umo_orden;

    -- Control: Plan de Hornos NO debe tener roles (debe salir vacío)
    SELECT 'DESPUES - debe salir vacío' AS momento, *
    FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod = @moduloPlanHornos;

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
-- COMMIT;
-- ROLLBACK;


-- ─── Después de COMMIT/ROLLBACK: confirmar que no quedó ninguna transacción abierta ───
SELECT s.session_id, s.login_name, s.host_name, s.program_name,
       t.transaction_begin_time, DB_NAME(dt.database_id) AS base,
       r.blocking_session_id
FROM sys.dm_tran_session_transactions st
JOIN sys.dm_tran_active_transactions t    ON t.transaction_id = st.transaction_id
JOIN sys.dm_tran_database_transactions dt ON dt.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s               ON s.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests r          ON r.session_id = st.session_id
WHERE DB_NAME(dt.database_id) = 'sm_seguridad'
ORDER BY t.transaction_begin_time;
