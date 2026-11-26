-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███
-- Administración → Seguridad como un módulo más (deja de depender de una lista fija de usuarios).
-- ════════════════════════════════════════════════════════════════════════════════════
-- CUÁNDO: ANTES de publicar smb_react. El frontend actual no lee este módulo (usa la lista fija),
--   así que nadie nota el cambio hasta publicar; al publicar, el usuario 29734 ya tiene acceso.
--
-- Qué hace (busca por nombre/path; los códigos se calculan, pueden diferir entre ambientes):
--   1. Crea el menú "Administración" si no existe.
--   2. Crea el módulo "Seguridad" (/admin/seguridad) en ese menú si no existe.
--   3. Crea el rol "Administrador de Seguridad" en cada negocio del usuario. Usa el MISMO código
--      en todos los negocios, mayor que cualquier código numérico existente, para no chocar con
--      roles de otros negocios (el módulo de Reportes mezcla códigos de rol entre negocios).
--   4. Le asigna al rol solo el módulo Seguridad.
--   5. Le asigna el rol al usuario 29734 en cada negocio, ADEMÁS de su rol actual (no lo reemplaza).
--      Negocios del usuario = los de sus tiendas o roles activos.
--   Quienes no tengan este rol dejan de ver Administración al publicar. Para dar acceso a otro
--   usuario: Administración → Seguridad → Usuarios, asignarle el rol "Administrador de Seguridad".
--
-- Idempotente. Corre en una transacción y NO confirma sola: revisar los SELECT de DESPUÉS y ejecutar
-- COMMIT o ROLLBACK al final. No dejar la transacción abierta: bloquea las tablas de seguridad.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

DECLARE @usuario     VARCHAR(20)   = '29734';
DECLARE @menuNombre  NVARCHAR(200) = N'Administración';
DECLARE @modPath     NVARCHAR(200) = N'/admin/seguridad';
DECLARE @rolNombre   NVARCHAR(200) = N'Administrador de Seguridad';

IF NOT EXISTS (SELECT 1 FROM sct.seg_usu_usuario WHERE usu_codigo = @usuario AND usu_estado = 1)
    THROW 50030, 'El usuario no existe o está inactivo en sct.seg_usu_usuario.', 1;

-- Negocios del usuario
DECLARE @negocios TABLE (codigo_neg INT PRIMARY KEY);
INSERT INTO @negocios (codigo_neg)
SELECT uti_codigo_neg FROM sct.seg_uti_usuario_tienda WHERE uti_codigo_usu = @usuario AND uti_estado = 1
UNION
SELECT uro_codigo_neg FROM sct.seg_uro_usuario_rol    WHERE uro_codigo_usu = @usuario AND uro_estado = 1;

-- Estado antes
SELECT 'ANTES' AS momento, n.codigo_neg, r.uro_codigo_rol, rl.rol_nombre
FROM @negocios n
LEFT JOIN sct.seg_uro_usuario_rol r ON r.uro_codigo_neg = n.codigo_neg AND r.uro_codigo_usu = @usuario
LEFT JOIN sct.seg_rol rl ON rl.rol_codigo_neg = r.uro_codigo_neg AND rl.rol_codigo = r.uro_codigo_rol
ORDER BY n.codigo_neg;

BEGIN TRAN;

    -- 1. Menú Administración
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre)
        INSERT INTO sct.seg_mnu_menu (mnu_codigo, mnu_nombre, mnu_descripcion, mnu_estado, mnu_created_at, mnu_updated_at)
        SELECT ISNULL(MAX(mnu_codigo), 0) + 1, @menuNombre, N'Administración del sistema', 1, GETDATE(), GETDATE()
        FROM sct.seg_mnu_menu;

    DECLARE @menu INT = (SELECT mnu_codigo FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre);

    -- 2. Módulo Seguridad
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo WHERE mod_path = @modPath)
    BEGIN
        DECLARE @modNuevo INT = (SELECT ISNULL(MAX(mod_codigo), 0) + 1 FROM sct.seg_mod_modulo);

        INSERT INTO sct.seg_mod_modulo
            (mod_codigo, mod_mnu_codigo, mod_nombre, mod_descripcion, mod_path, mod_estado, mod_orden, mod_visible, mod_created_at, mod_updated_at)
        VALUES
            (@modNuevo, @menu, N'Seguridad', N'Mantenimiento de menús, módulos, roles, privilegios y usuarios',
             @modPath, '1', CAST(@modNuevo AS VARCHAR(10)), 1, GETDATE(), GETDATE());
    END;

    DECLARE @modulo INT = (SELECT mod_codigo FROM sct.seg_mod_modulo WHERE mod_path = @modPath);
    DECLARE @menuModulo INT = (SELECT mod_mnu_codigo FROM sct.seg_mod_modulo WHERE mod_codigo = @modulo);

    -- 3. Rol: si ya existe en algún negocio se reutiliza su código; si no, uno nuevo para todos.
    DECLARE @rol VARCHAR(100) = (SELECT TOP (1) rol_codigo FROM sct.seg_rol WHERE rol_nombre = @rolNombre);
    IF @rol IS NULL
        SET @rol = CAST((SELECT ISNULL(MAX(TRY_CONVERT(INT, rol_codigo)), 0) + 1 FROM sct.seg_rol) AS VARCHAR(100));

    INSERT INTO sct.seg_rol (rol_codigo_neg, rol_codigo, rol_nombre, rol_descripcion, rol_estado, rol_created_at, rol_updated_at)
    SELECT n.codigo_neg, @rol, @rolNombre, N'Acceso a Administración → Seguridad', 1, GETDATE(), GETDATE()
    FROM @negocios n
    WHERE NOT EXISTS (SELECT 1 FROM sct.seg_rol r WHERE r.rol_codigo_neg = n.codigo_neg AND r.rol_codigo = @rol);

    -- 4. Módulo Seguridad al rol
    INSERT INTO sct.seg_rmo_rol_modulo
        (rmo_codigo_neg, rmo_codigo_rol, rmo_codigo_mnu, rmo_codigo_mod, rmo_estado, rmo_created_at, rmo_updated_at)
    SELECT n.codigo_neg, @rol, @menuModulo, @modulo, 1, GETDATE(), GETDATE()
    FROM @negocios n
    WHERE NOT EXISTS (SELECT 1 FROM sct.seg_rmo_rol_modulo x
                      WHERE x.rmo_codigo_neg = n.codigo_neg AND x.rmo_codigo_rol = @rol AND x.rmo_codigo_mod = @modulo);

    -- 5. Rol al usuario (además del que ya tiene)
    INSERT INTO sct.seg_uro_usuario_rol (uro_codigo_neg, uro_codigo_rol, uro_codigo_usu, uro_estado, uro_created_at, uro_updated_at)
    SELECT n.codigo_neg, @rol, @usuario, 1, GETDATE(), GETDATE()
    FROM @negocios n
    WHERE NOT EXISTS (SELECT 1 FROM sct.seg_uro_usuario_rol x
                      WHERE x.uro_codigo_neg = n.codigo_neg AND x.uro_codigo_rol = @rol AND x.uro_codigo_usu = @usuario);

    -- Estado después
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mnu_menu   WHERE mnu_codigo = @menu;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mod_modulo WHERE mod_codigo = @modulo;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_rol        WHERE rol_codigo = @rol ORDER BY rol_codigo_neg;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod = @modulo ORDER BY rmo_codigo_neg;

    -- Lo que verá la app: debe salir /admin/seguridad en cada negocio del usuario, junto con sus módulos actuales.
    SELECT 'DESPUES' AS momento, uro.uro_codigo_neg AS negocio, m.mod_path, m.mod_nombre
    FROM sct.seg_uro_usuario_rol uro
    JOIN sct.seg_rmo_rol_modulo rmo ON rmo.rmo_codigo_neg = uro.uro_codigo_neg AND rmo.rmo_codigo_rol = uro.uro_codigo_rol
    JOIN sct.seg_mod_modulo m       ON m.mod_codigo = rmo.rmo_codigo_mod
    WHERE uro.uro_codigo_usu = @usuario AND uro.uro_estado = 1 AND rmo.rmo_estado = 1
    ORDER BY uro.uro_codigo_neg, m.mod_path;

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
COMMIT;
-- ROLLBACK;


SELECT s.session_id, s.login_name, s.host_name, s.program_name,
       t.transaction_begin_time, DB_NAME(dt.database_id) AS base,
       r.blocking_session_id
FROM sys.dm_tran_session_transactions st
JOIN sys.dm_tran_active_transactions t   ON t.transaction_id = st.transaction_id
JOIN sys.dm_tran_database_transactions dt ON dt.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s              ON s.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests r         ON r.session_id = st.session_id
WHERE DB_NAME(dt.database_id) = 'sm_seguridad'
ORDER BY t.transaction_begin_time;

