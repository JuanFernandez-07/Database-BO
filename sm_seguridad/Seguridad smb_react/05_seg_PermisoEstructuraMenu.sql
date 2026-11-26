-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███          (5)
-- Permiso para administrar la ESTRUCTURA DEL MENÚ (solo Sistemas)
-- ════════════════════════════════════════════════════════════════════════════════════
-- Requiere 01 a 04 confirmados.
--
-- Crea el permiso admin.seguridad.estructura, acción de la pantalla Seguridad:
--   - smb_react muestra la pestaña "Estructura del menú" solo a quien lo tiene.
--   - smb_net exige el permiso para crear, editar, borrar o reordenar menús, submenús, módulos,
--     submódulos y permisos (con solo admin.seguridad.ver se administran roles y usuarios).
--
-- Se asigna a los roles POR NOMBRE (no por código: los códigos cambian entre dev y producción).
-- Ajustar @roles si el rol de Sistemas se llama distinto. También toma las variantes por negocio que
-- pudo dejar una migración anterior ("CDI Sistemas (Neg 1)", ...).
-- Después se puede dar o quitar desde Administración → Seguridad → Roles (aparece bajo Seguridad).
--
-- Idempotente. Transacción sin COMMIT automático.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

IF OBJECT_ID(N'seg.acc_per_permiso', N'U') IS NULL
    THROW 50090, 'No existe la estructura del esquema seg. Correr 01 a 04 primero.', 1;

DECLARE @usuarioScript VARCHAR(100) = 'SCRIPT';
DECLARE @clave         VARCHAR(150) = 'admin.seguridad.estructura';

DECLARE @roles TABLE (nombre NVARCHAR(200) PRIMARY KEY);
INSERT INTO @roles (nombre) VALUES
    (N'CDI Sistemas');

-- Roles que recibirán el permiso (nombre exacto o variante "Nombre (Neg x)")
DECLARE @destino TABLE (rol_codigo INT PRIMARY KEY, rol_nombre NVARCHAR(200));
INSERT INTO @destino (rol_codigo, rol_nombre)
SELECT r.rol_codigo, r.rol_nombre
FROM seg.acc_rol_rol r
JOIN @roles x ON r.rol_nombre = x.nombre OR r.rol_nombre LIKE x.nombre + N' (Neg %';

IF NOT EXISTS (SELECT 1 FROM @destino)
    THROW 50091, 'No se encontró ningún rol con los nombres de @roles. Revisar el nombre del rol de Sistemas.', 1;

BEGIN TRAN;

    -- 1. Permiso (mismo grupo que el resto de Administración)
    IF NOT EXISTS (SELECT 1 FROM seg.acc_per_permiso WHERE per_clave = @clave)
        INSERT INTO seg.acc_per_permiso (per_clave, per_nombre, per_descripcion, per_grupo, per_estado, per_created_by, per_updated_by)
        VALUES (@clave, N'Administrar estructura del menú',
                N'Crear, editar, ordenar y eliminar menús, submenús, módulos, submódulos y sus acciones.',
                N'Administración', 1, @usuarioScript, @usuarioScript);

    DECLARE @permiso INT = (SELECT per_codigo FROM seg.acc_per_permiso WHERE per_clave = @clave);

    -- 2. Asignarlo a los roles de Sistemas
    INSERT INTO seg.acc_rpe_rol_permiso (rpe_codigo_rol, rpe_codigo_per, rpe_created_by)
    SELECT d.rol_codigo, @permiso, @usuarioScript
    FROM @destino d
    WHERE NOT EXISTS (SELECT 1 FROM seg.acc_rpe_rol_permiso x WHERE x.rpe_codigo_rol = d.rol_codigo AND x.rpe_codigo_per = @permiso);

    -- ─── Verificación ────────────────────────────────────────────────────────

    -- Roles con el permiso
    SELECT 'DESPUES' AS momento, r.rol_codigo, r.rol_nombre
    FROM seg.acc_rpe_rol_permiso rpe
    JOIN seg.acc_rol_rol r ON r.rol_codigo = rpe.rpe_codigo_rol
    WHERE rpe.rpe_codigo_per = @permiso
    ORDER BY r.rol_nombre;

    -- Usuarios que verán la pestaña "Estructura del menú" (y en qué negocios).
    -- Para verla también necesitan admin.seguridad.ver (acceso a la pantalla Seguridad).
    SELECT 'DESPUES' AS momento, uro.uro_codigo_usu AS usuario, uro.uro_codigo_neg AS negocio, r.rol_nombre,
           CASE WHEN EXISTS (
                    SELECT 1 FROM seg.acc_uro_usuario_rol u2
                    JOIN seg.acc_rpe_rol_permiso p2 ON p2.rpe_codigo_rol = u2.uro_codigo_rol
                    JOIN seg.acc_per_permiso pv     ON pv.per_codigo = p2.rpe_codigo_per AND pv.per_clave = 'admin.seguridad.ver'
                    WHERE u2.uro_codigo_usu = uro.uro_codigo_usu AND u2.uro_codigo_neg = uro.uro_codigo_neg AND u2.uro_estado = 1)
                THEN 'Sí' ELSE 'NO - le falta admin.seguridad.ver' END AS entra_a_seguridad
    FROM seg.acc_uro_usuario_rol uro
    JOIN @destino d        ON d.rol_codigo = uro.uro_codigo_rol
    JOIN seg.acc_rol_rol r ON r.rol_codigo = uro.uro_codigo_rol
    WHERE uro.uro_estado = 1
    ORDER BY uro.uro_codigo_usu, uro.uro_codigo_neg;

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
