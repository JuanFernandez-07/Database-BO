-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███          (3 de 3)
-- Seguridad y navegación propias de smb_react / smb_net — MIGRACIÓN de roles y asignaciones
-- ════════════════════════════════════════════════════════════════════════════════════
-- Requiere 01 y 02 confirmados. Solo LEE el modelo anterior (sct); solo ESCRIBE en seg.
--
-- Reglas (genéricas, sin códigos fijos: sirve igual en dev y en producción):
--   1. Solo se migra lo que corresponde a pantallas de smb_react (lo que está en
--      seg.acc_peq_permiso_equivalencia). Roles que solo tienen módulos de Laravel no se migran;
--      de un rol mixto pasa únicamente su parte de smb_react.
--   2. Permisos de un rol anterior en un negocio = pantallas (seg_rmo_rol_modulo activo)
--      + privilegios (SEG_RPR_ROL_PRIVILEGIO activo o NULL) de ESE negocio.
--   3. Solo roles anteriores activos (rol_estado = 1) y asignaciones activas (uro_estado = 1)
--      de usuarios que existan en sct.seg_usu_usuario.
--   4. Roles con el mismo nombre → UN solo rol nuevo (los roles ya no son por negocio).
--      Si sus permisos eran distintos según el negocio, el rol nuevo recibe la UNIÓN: nadie pierde
--      accesos, pero alguien puede ganar en un negocio donde tenía menos (ver validación A2).
--   5. Usuario + rol anterior + negocio → usuario + rol nuevo + mismo negocio.
--
-- Reejecutable mientras el modelo nuevo no esté en uso: borra lo migrado antes y lo reconstruye.
-- Se niega a correr si encuentra roles o asignaciones creados por alguien distinto de MIGRACION
-- (es decir, si ya se administró desde smb_react).
--
-- Validaciones al final:
--   A.  Nadie pierde (debe salir VACÍA): permisos que un usuario tenía en un negocio y ya no tiene.
--   A2. Informativa: permisos que un usuario GANA en un negocio por unificar roles con el mismo
--       nombre. Revisar antes del COMMIT; si alguno no corresponde, se ajusta después en Roles.
--   B. Informativa: privilegios que hoy smb_net concede desde OTRO negocio (defecto actual de
--      GetPrivilegiosUsuarioAsync, que no filtra por negocio). Con el modelo nuevo dejan de aplicar.
--   C. Informativa: roles inactivos que hoy dan acceso en smb_react (smb_net no revisa rol_estado).
--
-- Transacción sin COMMIT automático.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

DECLARE @usuarioScript VARCHAR(100) = 'MIGRACION';

IF NOT EXISTS (SELECT 1 FROM seg.acc_peq_permiso_equivalencia)
    THROW 50070, 'No hay catálogo de permisos. Correr y confirmar primero 02_seg_Catalogo.sql.', 1;

IF EXISTS (SELECT 1 FROM seg.acc_rol_rol         WHERE rol_created_by <> @usuarioScript)
   OR EXISTS (SELECT 1 FROM seg.acc_uro_usuario_rol WHERE uro_created_by <> @usuarioScript)
    THROW 50071, 'El modelo nuevo ya tiene roles o asignaciones creados fuera de la migración. No se reconstruye para no perder esos cambios.', 1;

DROP TABLE IF EXISTS #otorgado;
DROP TABLE IF EXISTS #rolNeg;
DROP TABLE IF EXISTS #rolNuevo;

BEGIN TRAN;

    -- ─── 0. Reconstrucción: quitar lo migrado anteriormente ─────────────────
    DELETE FROM seg.acc_uro_usuario_rol;      -- todo es de MIGRACION (validado arriba)
    DELETE FROM seg.acc_rol_rol;              -- cascada: acc_rpe_rol_permiso y acc_rmi_rol_migracion

    -- ─── 1. Permisos de cada rol anterior en cada negocio (solo smb_react) ──
    -- COLLATE DATABASE_DEFAULT: tempdb puede tener otra collation que sm_seguridad
    CREATE TABLE #otorgado (
        neg INT          NOT NULL,
        rol VARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL,
        per INT          NOT NULL,
        PRIMARY KEY (neg, rol, per)
    );

    INSERT INTO #otorgado (neg, rol, per)
    SELECT rmo.rmo_codigo_neg, rmo.rmo_codigo_rol, peq.peq_codigo_per
    FROM sct.seg_rmo_rol_modulo rmo
    JOIN sct.seg_mod_modulo m                    ON m.mod_codigo = rmo.rmo_codigo_mod
    JOIN seg.acc_peq_permiso_equivalencia peq    ON peq.peq_mod_path = m.mod_path
                                                AND peq.peq_codigo_pri_anterior IS NULL
    WHERE rmo.rmo_estado = 1
    UNION
    SELECT rpr.rpr_codigo_neg, rpr.rpr_codigo_rol, peq.peq_codigo_per
    FROM sct.SEG_RPR_ROL_PRIVILEGIO rpr
    JOIN sct.seg_mod_modulo m                    ON m.mod_codigo = rpr.rpr_codigo_mod
    JOIN seg.acc_peq_permiso_equivalencia peq    ON peq.peq_mod_path = m.mod_path
                                                AND peq.peq_codigo_pri_anterior = rpr.rpr_codigo_pri
    WHERE rpr.rpr_estado IS NULL OR rpr.rpr_estado = 1;

    -- ─── 2. Firma de permisos por rol anterior activo y negocio ─────────────
    CREATE TABLE #rolNeg (
        neg    INT           NOT NULL,
        rol    VARCHAR(100)  COLLATE DATABASE_DEFAULT NOT NULL,
        nombre NVARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        firma  VARCHAR(1000) COLLATE DATABASE_DEFAULT NOT NULL,
        PRIMARY KEY (neg, rol)
    );

    INSERT INTO #rolNeg (neg, rol, nombre, firma)
    SELECT o.neg, o.rol, LTRIM(RTRIM(r.rol_nombre)),
           STRING_AGG(CAST(o.per AS VARCHAR(10)), ',') WITHIN GROUP (ORDER BY o.per)
    FROM #otorgado o
    JOIN sct.seg_rol r ON r.rol_codigo_neg = o.neg AND r.rol_codigo = o.rol
    WHERE r.rol_estado = 1
    GROUP BY o.neg, o.rol, LTRIM(RTRIM(r.rol_nombre));

    -- ─── 3. Un rol nuevo por nombre (sin importar el negocio) ───────────────
    -- variantes > 1: el mismo nombre tenía permisos distintos según el negocio; se unifica con la unión.
    CREATE TABLE #rolNuevo (
        nombre    NVARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
        negocios  VARCHAR(200)  COLLATE DATABASE_DEFAULT NOT NULL,
        variantes INT           NOT NULL
    );

    INSERT INTO #rolNuevo (nombre, negocios, variantes)
    SELECT nombre,
           STRING_AGG(CAST(neg AS VARCHAR(10)), ', ') WITHIN GROUP (ORDER BY neg),
           COUNT(DISTINCT firma)
    FROM #rolNeg
    GROUP BY nombre;

    -- ─── 4. Roles nuevos ────────────────────────────────────────────────────
    INSERT INTO seg.acc_rol_rol (rol_nombre, rol_descripcion, rol_estado, rol_created_by, rol_updated_by)
    -- La descripción queda vacía: el origen de cada rol queda en seg.acc_rmi_rol_migracion.
    SELECT r.nombre, NULL, 1, @usuarioScript, @usuarioScript
    FROM #rolNuevo r;

    -- ─── 5. Trazabilidad rol anterior (negocio, código) → rol nuevo ─────────
    INSERT INTO seg.acc_rmi_rol_migracion (rmi_codigo_neg, rmi_codigo_rol_anterior, rmi_codigo_rol, rmi_firma)
    SELECT rn.neg, rn.rol, nr.rol_codigo, rn.firma
    FROM #rolNeg rn
    JOIN seg.acc_rol_rol nr ON nr.rol_nombre = rn.nombre;

    -- ─── 6. Permisos de cada rol nuevo ──────────────────────────────────────
    INSERT INTO seg.acc_rpe_rol_permiso (rpe_codigo_rol, rpe_codigo_per, rpe_created_by)
    SELECT DISTINCT rmi.rmi_codigo_rol, o.per, @usuarioScript
    FROM seg.acc_rmi_rol_migracion rmi
    JOIN #otorgado o ON o.neg = rmi.rmi_codigo_neg AND o.rol = rmi.rmi_codigo_rol_anterior;

    -- ─── 7. Asignaciones usuario + rol + negocio ────────────────────────────
    INSERT INTO seg.acc_uro_usuario_rol (uro_codigo_usu, uro_codigo_rol, uro_codigo_neg, uro_estado, uro_created_by, uro_updated_by)
    SELECT DISTINCT uro.uro_codigo_usu, rmi.rmi_codigo_rol, uro.uro_codigo_neg, 1, @usuarioScript, @usuarioScript
    FROM sct.seg_uro_usuario_rol uro
    JOIN seg.acc_rmi_rol_migracion rmi ON rmi.rmi_codigo_neg = uro.uro_codigo_neg
                                      AND rmi.rmi_codigo_rol_anterior = uro.uro_codigo_rol
    WHERE uro.uro_estado = 1
      AND EXISTS (SELECT 1 FROM sct.seg_usu_usuario u WHERE u.usu_codigo = uro.uro_codigo_usu);

    -- ════════════════════════════════════════════════════════════════════════
    -- REPORTES
    -- ════════════════════════════════════════════════════════════════════════

    -- Resumen
    SELECT 'DESPUES' AS momento,
           (SELECT COUNT(*) FROM seg.acc_rol_rol)                          AS roles_nuevos,
           (SELECT COUNT(*) FROM seg.acc_rpe_rol_permiso)                  AS rol_permisos,
           (SELECT COUNT(*) FROM seg.acc_uro_usuario_rol)                  AS asignaciones,
           (SELECT COUNT(DISTINCT uro_codigo_usu) FROM seg.acc_uro_usuario_rol) AS usuarios;

    -- Roles nuevos: origen, permisos y usuarios
    SELECT 'DESPUES' AS momento, r.rol_codigo, r.rol_nombre,
           v.negocios,
           CASE WHEN v.variantes > 1 THEN 'REVISAR: tenía permisos distintos por negocio; se unificó (ver A2)' ELSE '' END AS observacion,
           (SELECT STRING_AGG(p.per_clave, ', ') WITHIN GROUP (ORDER BY p.per_clave)
            FROM seg.acc_rpe_rol_permiso rpe JOIN seg.acc_per_permiso p ON p.per_codigo = rpe.rpe_codigo_per
            WHERE rpe.rpe_codigo_rol = r.rol_codigo) AS permisos,
           (SELECT COUNT(DISTINCT u.uro_codigo_usu) FROM seg.acc_uro_usuario_rol u
            WHERE u.uro_codigo_rol = r.rol_codigo) AS usuarios
    FROM seg.acc_rol_rol r
    JOIN #rolNuevo v ON v.nombre = r.rol_nombre
    ORDER BY r.rol_nombre;

    -- ─── A / A2. Permisos por usuario y negocio, antes vs después ───────────
    WITH antes AS (
        SELECT DISTINCT uro.uro_codigo_usu AS usu, uro.uro_codigo_neg AS neg, o.per
        FROM sct.seg_uro_usuario_rol uro
        JOIN #rolNeg rn   ON rn.neg = uro.uro_codigo_neg AND rn.rol = uro.uro_codigo_rol
        JOIN #otorgado o  ON o.neg = rn.neg AND o.rol = rn.rol
        WHERE uro.uro_estado = 1
          AND EXISTS (SELECT 1 FROM sct.seg_usu_usuario u WHERE u.usu_codigo = uro.uro_codigo_usu)
    ),
    despues AS (
        SELECT DISTINCT u.uro_codigo_usu AS usu, u.uro_codigo_neg AS neg, rpe.rpe_codigo_per AS per
        FROM seg.acc_uro_usuario_rol u
        JOIN seg.acc_rpe_rol_permiso rpe ON rpe.rpe_codigo_rol = u.uro_codigo_rol
        WHERE u.uro_estado = 1
    ),
    diferencias AS (
        SELECT 'A. PIERDE - debe salir vacío' AS validacion, usu, neg, per
        FROM (SELECT usu, neg, per FROM antes EXCEPT SELECT usu, neg, per FROM despues) a
        UNION ALL
        SELECT 'A2. GANA por unificar roles (informativo)' AS validacion, usu, neg, per
        FROM (SELECT usu, neg, per FROM despues EXCEPT SELECT usu, neg, per FROM antes) d
    )
    SELECT d.validacion, d.usu, d.neg, p.per_clave
    FROM diferencias d
    JOIN seg.acc_per_permiso p ON p.per_codigo = d.per
    ORDER BY d.validacion, d.usu, d.neg, p.per_clave;

    -- ─── B. Privilegios que hoy llegan desde otro negocio (informativo) ─────
    WITH privilegios_hoy AS (   -- lógica actual de smb_net: privilegios del usuario en cualquier negocio
        SELECT DISTINCT uro.uro_codigo_usu AS usu, o.per
        FROM sct.seg_uro_usuario_rol uro
        JOIN #otorgado o ON o.neg = uro.uro_codigo_neg AND o.rol = uro.uro_codigo_rol
        JOIN seg.acc_peq_permiso_equivalencia peq ON peq.peq_codigo_per = o.per AND peq.peq_codigo_pri_anterior IS NOT NULL
        WHERE uro.uro_estado = 1
    ),
    negocios_usuario AS (
        SELECT DISTINCT uro_codigo_usu AS usu, uro_codigo_neg AS neg FROM seg.acc_uro_usuario_rol
    ),
    despues AS (
        SELECT DISTINCT u.uro_codigo_usu AS usu, u.uro_codigo_neg AS neg, rpe.rpe_codigo_per AS per
        FROM seg.acc_uro_usuario_rol u
        JOIN seg.acc_rpe_rol_permiso rpe ON rpe.rpe_codigo_rol = u.uro_codigo_rol
    ),
    perdidos AS (
        SELECT n.usu, n.neg, h.per FROM negocios_usuario n JOIN privilegios_hoy h ON h.usu = n.usu
        EXCEPT
        SELECT usu, neg, per FROM despues
    )
    SELECT 'B. INFORMATIVO - hoy lo tiene por el defecto de negocio; en el modelo nuevo no' AS validacion,
           x.usu, x.neg, p.per_clave
    FROM perdidos x
    JOIN seg.acc_per_permiso p ON p.per_codigo = x.per
    ORDER BY x.usu, x.neg, p.per_clave;

    -- ─── C. Roles inactivos que hoy dan acceso en smb_react (informativo) ───
    SELECT 'C. INFORMATIVO - rol inactivo, no se migra' AS validacion,
           r.rol_codigo_neg, r.rol_codigo, r.rol_nombre,
           (SELECT COUNT(*) FROM sct.seg_uro_usuario_rol u
            WHERE u.uro_codigo_neg = r.rol_codigo_neg AND u.uro_codigo_rol = r.rol_codigo AND u.uro_estado = 1) AS usuarios_activos
    FROM sct.seg_rol r
    WHERE ISNULL(r.rol_estado, 0) <> 1
      AND EXISTS (SELECT 1 FROM #otorgado o WHERE o.neg = r.rol_codigo_neg AND o.rol = r.rol_codigo)
    ORDER BY r.rol_nombre, r.rol_codigo_neg;

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
