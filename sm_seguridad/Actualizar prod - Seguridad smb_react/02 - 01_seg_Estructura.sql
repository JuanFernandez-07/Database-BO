-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad ███          (1 de 3)
-- Seguridad y navegación propias de smb_react / smb_net — ESTRUCTURA
-- ════════════════════════════════════════════════════════════════════════════════════
-- Crea el esquema `seg` y sus tablas. Solo lo usan smb_react y smb_net.
-- NO modifica, NO agrega restricciones y NO crea FK hacia tablas del esquema `sct`
-- (las que usa smb-laravel). La identidad (usuarios, negocios, tiendas) se sigue leyendo de `sct`
-- y se referencia de forma lógica (sin FK).
--
-- Navegación (cada nodo solo indica qué permiso necesita para verse; no es seguridad):
--   seg.nav_mnu_menu        Menú            (nivel 1)
--   seg.nav_smn_submenu     Submenú         (nivel 2, opcional, solo ordena)
--   seg.nav_mod_modulo      Módulo          (nivel 3; sin permiso "ver" = agrupador)
--   seg.nav_smo_submodulo   Submódulo       (nivel 4, siempre pantalla)
-- Seguridad (RBAC con alcance por negocio):
--   seg.acc_per_permiso             Permiso con clave de texto (plan-hornos.devolucion.cerrar-dia-cocina)
--   seg.acc_rol_rol                 Rol global (definido una sola vez)
--   seg.acc_rpe_rol_permiso         Permisos de cada rol
--   seg.acc_uro_usuario_rol         Usuario + rol + negocio
-- Migración (trazabilidad con el modelo anterior):
--   seg.acc_peq_permiso_equivalencia  path/privilegio anterior → permiso nuevo
--   seg.acc_rmi_rol_migracion         rol anterior (negocio, código) → rol nuevo
--
-- Idempotente. Corre en una transacción y NO confirma sola: ejecutar COMMIT o ROLLBACK al final.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

BEGIN TRAN;

    IF SCHEMA_ID(N'seg') IS NULL
        EXEC (N'CREATE SCHEMA seg AUTHORIZATION dbo');

    -- ─── Navegación ──────────────────────────────────────────────────────────

    IF OBJECT_ID(N'seg.nav_mnu_menu', N'U') IS NULL
        CREATE TABLE seg.nav_mnu_menu (
            mnu_codigo       INT IDENTITY(1,1) NOT NULL,
            mnu_nombre       NVARCHAR(150)     NOT NULL,
            mnu_descripcion  NVARCHAR(300)     NULL,
            mnu_icono        NVARCHAR(100)     NULL,
            mnu_orden        INT               NOT NULL CONSTRAINT DF_nav_mnu_menu_orden      DEFAULT (0),
            mnu_estado       BIT               NOT NULL CONSTRAINT DF_nav_mnu_menu_estado     DEFAULT (1),
            mnu_created_by   VARCHAR(100)      NOT NULL,
            mnu_created_at   DATETIME          NOT NULL CONSTRAINT DF_nav_mnu_menu_created_at DEFAULT (GETDATE()),
            mnu_updated_by   VARCHAR(100)      NOT NULL,
            mnu_updated_at   DATETIME          NOT NULL CONSTRAINT DF_nav_mnu_menu_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_nav_mnu_menu        PRIMARY KEY CLUSTERED (mnu_codigo),
            CONSTRAINT UQ_nav_mnu_menu_nombre UNIQUE (mnu_nombre)
        );

    IF OBJECT_ID(N'seg.nav_smn_submenu', N'U') IS NULL
    BEGIN
        CREATE TABLE seg.nav_smn_submenu (
            smn_codigo       INT IDENTITY(1,1) NOT NULL,
            smn_codigo_mnu   INT               NOT NULL,
            smn_nombre       NVARCHAR(150)     NOT NULL,
            smn_descripcion  NVARCHAR(300)     NULL,
            smn_icono        NVARCHAR(100)     NULL,
            smn_orden        INT               NOT NULL CONSTRAINT DF_nav_smn_submenu_orden      DEFAULT (0),
            smn_estado       BIT               NOT NULL CONSTRAINT DF_nav_smn_submenu_estado     DEFAULT (1),
            smn_created_by   VARCHAR(100)      NOT NULL,
            smn_created_at   DATETIME          NOT NULL CONSTRAINT DF_nav_smn_submenu_created_at DEFAULT (GETDATE()),
            smn_updated_by   VARCHAR(100)      NOT NULL,
            smn_updated_at   DATETIME          NOT NULL CONSTRAINT DF_nav_smn_submenu_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_nav_smn_submenu             PRIMARY KEY CLUSTERED (smn_codigo),
            CONSTRAINT FK_nav_smn_submenu_menu        FOREIGN KEY (smn_codigo_mnu) REFERENCES seg.nav_mnu_menu (mnu_codigo),
            CONSTRAINT UQ_nav_smn_submenu_menu_nombre UNIQUE (smn_codigo_mnu, smn_nombre),
            -- Destino de la FK compuesta de nav_mod_modulo (módulo y submenú en el mismo menú)
            CONSTRAINT UQ_nav_smn_submenu_codigo_menu UNIQUE (smn_codigo, smn_codigo_mnu)
        );
    END;

    -- ─── Seguridad: permisos (antes que módulos, por las FK) ─────────────────

    IF OBJECT_ID(N'seg.acc_per_permiso', N'U') IS NULL
        CREATE TABLE seg.acc_per_permiso (
            per_codigo       INT IDENTITY(1,1) NOT NULL,
            per_clave        VARCHAR(150)      NOT NULL,   -- plan-hornos.devolucion.cerrar-dia-cocina
            per_nombre       NVARCHAR(150)     NOT NULL,   -- Cerrar día de cocina
            per_descripcion  NVARCHAR(300)     NULL,
            per_grupo        NVARCHAR(100)     NULL,       -- para agrupar en la administración
            per_estado       BIT               NOT NULL CONSTRAINT DF_acc_per_permiso_estado     DEFAULT (1),
            per_created_by   VARCHAR(100)      NOT NULL,
            per_created_at   DATETIME          NOT NULL CONSTRAINT DF_acc_per_permiso_created_at DEFAULT (GETDATE()),
            per_updated_by   VARCHAR(100)      NOT NULL,
            per_updated_at   DATETIME          NOT NULL CONSTRAINT DF_acc_per_permiso_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_per_permiso       PRIMARY KEY CLUSTERED (per_codigo),
            CONSTRAINT UQ_acc_per_permiso_clave UNIQUE (per_clave)
        );

    IF OBJECT_ID(N'seg.nav_mod_modulo', N'U') IS NULL
    BEGIN
        CREATE TABLE seg.nav_mod_modulo (
            mod_codigo          INT IDENTITY(1,1) NOT NULL,
            mod_codigo_mnu      INT               NOT NULL,
            mod_codigo_smn      INT               NULL,       -- NULL = directo bajo el menú
            mod_codigo_per_ver  INT               NULL,       -- NULL = agrupador (se ve si algún submódulo se ve)
            mod_nombre          NVARCHAR(150)     NOT NULL,
            mod_descripcion     NVARCHAR(300)     NULL,
            mod_path            NVARCHAR(200)     NULL,
            mod_icono           NVARCHAR(100)     NULL,
            mod_orden           INT               NOT NULL CONSTRAINT DF_nav_mod_modulo_orden      DEFAULT (0),
            mod_estado          BIT               NOT NULL CONSTRAINT DF_nav_mod_modulo_estado     DEFAULT (1),
            mod_created_by      VARCHAR(100)      NOT NULL,
            mod_created_at      DATETIME          NOT NULL CONSTRAINT DF_nav_mod_modulo_created_at DEFAULT (GETDATE()),
            mod_updated_by      VARCHAR(100)      NOT NULL,
            mod_updated_at      DATETIME          NOT NULL CONSTRAINT DF_nav_mod_modulo_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_nav_mod_modulo         PRIMARY KEY CLUSTERED (mod_codigo),
            CONSTRAINT FK_nav_mod_modulo_menu    FOREIGN KEY (mod_codigo_mnu) REFERENCES seg.nav_mnu_menu (mnu_codigo),
            -- El submenú debe ser del mismo menú (si mod_codigo_smn es NULL no se evalúa)
            CONSTRAINT FK_nav_mod_modulo_submenu FOREIGN KEY (mod_codigo_smn, mod_codigo_mnu)
                REFERENCES seg.nav_smn_submenu (smn_codigo, smn_codigo_mnu),
            CONSTRAINT FK_nav_mod_modulo_permiso FOREIGN KEY (mod_codigo_per_ver) REFERENCES seg.acc_per_permiso (per_codigo)
        );

        CREATE UNIQUE NONCLUSTERED INDEX UX_nav_mod_modulo_path ON seg.nav_mod_modulo (mod_path) WHERE mod_path IS NOT NULL;
        CREATE NONCLUSTERED INDEX IX_nav_mod_modulo_menu    ON seg.nav_mod_modulo (mod_codigo_mnu, mod_codigo_smn);
        CREATE NONCLUSTERED INDEX IX_nav_mod_modulo_permiso ON seg.nav_mod_modulo (mod_codigo_per_ver);
    END;

    IF OBJECT_ID(N'seg.nav_smo_submodulo', N'U') IS NULL
    BEGIN
        CREATE TABLE seg.nav_smo_submodulo (
            smo_codigo          INT IDENTITY(1,1) NOT NULL,
            smo_codigo_mod      INT               NOT NULL,
            smo_codigo_per_ver  INT               NOT NULL,   -- un submódulo siempre es pantalla
            smo_nombre          NVARCHAR(150)     NOT NULL,
            smo_descripcion     NVARCHAR(300)     NULL,
            smo_path            NVARCHAR(200)     NOT NULL,
            smo_icono           NVARCHAR(100)     NULL,
            smo_orden           INT               NOT NULL CONSTRAINT DF_nav_smo_submodulo_orden      DEFAULT (0),
            smo_estado          BIT               NOT NULL CONSTRAINT DF_nav_smo_submodulo_estado     DEFAULT (1),
            smo_created_by      VARCHAR(100)      NOT NULL,
            smo_created_at      DATETIME          NOT NULL CONSTRAINT DF_nav_smo_submodulo_created_at DEFAULT (GETDATE()),
            smo_updated_by      VARCHAR(100)      NOT NULL,
            smo_updated_at      DATETIME          NOT NULL CONSTRAINT DF_nav_smo_submodulo_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_nav_smo_submodulo         PRIMARY KEY CLUSTERED (smo_codigo),
            CONSTRAINT FK_nav_smo_submodulo_modulo  FOREIGN KEY (smo_codigo_mod)     REFERENCES seg.nav_mod_modulo (mod_codigo),
            CONSTRAINT FK_nav_smo_submodulo_permiso FOREIGN KEY (smo_codigo_per_ver) REFERENCES seg.acc_per_permiso (per_codigo),
            CONSTRAINT UQ_nav_smo_submodulo_path    UNIQUE (smo_path)
        );

        CREATE NONCLUSTERED INDEX IX_nav_smo_submodulo_modulo  ON seg.nav_smo_submodulo (smo_codigo_mod);
        CREATE NONCLUSTERED INDEX IX_nav_smo_submodulo_permiso ON seg.nav_smo_submodulo (smo_codigo_per_ver);
    END;

    -- ─── Seguridad: roles y asignaciones ─────────────────────────────────────

    IF OBJECT_ID(N'seg.acc_rol_rol', N'U') IS NULL
        CREATE TABLE seg.acc_rol_rol (
            rol_codigo       INT IDENTITY(1,1) NOT NULL,
            rol_nombre       NVARCHAR(200)     NOT NULL,
            rol_descripcion  NVARCHAR(300)     NULL,
            rol_estado       BIT               NOT NULL CONSTRAINT DF_acc_rol_rol_estado     DEFAULT (1),
            rol_created_by   VARCHAR(100)      NOT NULL,
            rol_created_at   DATETIME          NOT NULL CONSTRAINT DF_acc_rol_rol_created_at DEFAULT (GETDATE()),
            rol_updated_by   VARCHAR(100)      NOT NULL,
            rol_updated_at   DATETIME          NOT NULL CONSTRAINT DF_acc_rol_rol_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_rol_rol        PRIMARY KEY CLUSTERED (rol_codigo),
            CONSTRAINT UQ_acc_rol_rol_nombre UNIQUE (rol_nombre)
        );

    IF OBJECT_ID(N'seg.acc_rpe_rol_permiso', N'U') IS NULL
    BEGIN
        CREATE TABLE seg.acc_rpe_rol_permiso (
            rpe_codigo_rol   INT          NOT NULL,
            rpe_codigo_per   INT          NOT NULL,
            rpe_created_by   VARCHAR(100) NOT NULL,
            rpe_created_at   DATETIME     NOT NULL CONSTRAINT DF_acc_rpe_rol_permiso_created_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_rpe_rol_permiso         PRIMARY KEY CLUSTERED (rpe_codigo_rol, rpe_codigo_per),
            CONSTRAINT FK_acc_rpe_rol_permiso_rol     FOREIGN KEY (rpe_codigo_rol) REFERENCES seg.acc_rol_rol (rol_codigo) ON DELETE CASCADE,
            CONSTRAINT FK_acc_rpe_rol_permiso_permiso FOREIGN KEY (rpe_codigo_per) REFERENCES seg.acc_per_permiso (per_codigo)
        );

        CREATE NONCLUSTERED INDEX IX_acc_rpe_rol_permiso_permiso ON seg.acc_rpe_rol_permiso (rpe_codigo_per);
    END;

    IF OBJECT_ID(N'seg.acc_uro_usuario_rol', N'U') IS NULL
    BEGIN
        CREATE TABLE seg.acc_uro_usuario_rol (
            uro_codigo       INT IDENTITY(1,1) NOT NULL,
            uro_codigo_usu   VARCHAR(100)      NOT NULL,   -- sct.seg_usu_usuario.usu_codigo (lógica, sin FK)
            uro_codigo_rol   INT               NOT NULL,
            uro_codigo_neg   INT               NOT NULL,   -- alcance: negocio (lógica, sin FK)
            uro_estado       BIT               NOT NULL CONSTRAINT DF_acc_uro_usuario_rol_estado     DEFAULT (1),
            uro_created_by   VARCHAR(100)      NOT NULL,
            uro_created_at   DATETIME          NOT NULL CONSTRAINT DF_acc_uro_usuario_rol_created_at DEFAULT (GETDATE()),
            uro_updated_by   VARCHAR(100)      NOT NULL,
            uro_updated_at   DATETIME          NOT NULL CONSTRAINT DF_acc_uro_usuario_rol_updated_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_uro_usuario_rol         PRIMARY KEY CLUSTERED (uro_codigo),
            CONSTRAINT FK_acc_uro_usuario_rol_rol     FOREIGN KEY (uro_codigo_rol) REFERENCES seg.acc_rol_rol (rol_codigo),
            CONSTRAINT UQ_acc_uro_usuario_rol_usu_rol_neg UNIQUE (uro_codigo_usu, uro_codigo_rol, uro_codigo_neg)
        );

        -- Consulta principal: permisos de un usuario en un negocio
        CREATE NONCLUSTERED INDEX IX_acc_uro_usuario_rol_usu_neg ON seg.acc_uro_usuario_rol (uro_codigo_usu, uro_codigo_neg)
            INCLUDE (uro_codigo_rol, uro_estado);
        CREATE NONCLUSTERED INDEX IX_acc_uro_usuario_rol_rol ON seg.acc_uro_usuario_rol (uro_codigo_rol);
    END;

    -- ─── Migración ───────────────────────────────────────────────────────────

    IF OBJECT_ID(N'seg.acc_peq_permiso_equivalencia', N'U') IS NULL
        CREATE TABLE seg.acc_peq_permiso_equivalencia (
            peq_codigo               INT IDENTITY(1,1) NOT NULL,
            peq_mod_path             NVARCHAR(200)     NOT NULL,  -- sct.seg_mod_modulo.mod_path
            peq_codigo_pri_anterior  INT               NULL,      -- NULL = acceso a la pantalla (seg_rmo_rol_modulo)
            peq_codigo_per           INT               NOT NULL,
            peq_created_at           DATETIME          NOT NULL CONSTRAINT DF_acc_peq_permiso_equivalencia_created_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_peq_permiso_equivalencia         PRIMARY KEY CLUSTERED (peq_codigo),
            CONSTRAINT FK_acc_peq_permiso_equivalencia_permiso FOREIGN KEY (peq_codigo_per) REFERENCES seg.acc_per_permiso (per_codigo),
            CONSTRAINT UQ_acc_peq_permiso_equivalencia_origen  UNIQUE (peq_mod_path, peq_codigo_pri_anterior)
        );

    IF OBJECT_ID(N'seg.acc_rmi_rol_migracion', N'U') IS NULL
        CREATE TABLE seg.acc_rmi_rol_migracion (
            rmi_codigo_neg           INT           NOT NULL,   -- sct.seg_rol.rol_codigo_neg
            rmi_codigo_rol_anterior  VARCHAR(100)  NOT NULL,   -- sct.seg_rol.rol_codigo
            rmi_codigo_rol           INT           NOT NULL,
            rmi_firma                VARCHAR(1000) NOT NULL,   -- permisos del rol anterior en ese negocio
            rmi_created_at           DATETIME      NOT NULL CONSTRAINT DF_acc_rmi_rol_migracion_created_at DEFAULT (GETDATE()),
            CONSTRAINT PK_acc_rmi_rol_migracion     PRIMARY KEY CLUSTERED (rmi_codigo_neg, rmi_codigo_rol_anterior),
            CONSTRAINT FK_acc_rmi_rol_migracion_rol FOREIGN KEY (rmi_codigo_rol) REFERENCES seg.acc_rol_rol (rol_codigo) ON DELETE CASCADE
        );

    -- Verificación
    SELECT 'DESPUES' AS momento, t.name AS tabla,
           (SELECT COUNT(*) FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id) AS fks,
           (SELECT COUNT(*) FROM sys.indexes i WHERE i.object_id = t.object_id AND i.index_id > 0) AS indices
    FROM sys.tables t
    WHERE t.schema_id = SCHEMA_ID(N'seg')
    ORDER BY t.name;

    -- Control: ninguna FK del esquema seg debe apuntar a sct (debe salir vacío)
    SELECT 'DESPUES - debe salir vacío' AS momento, fk.name, OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS esquema_destino
    FROM sys.foreign_keys fk
    WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'seg'
      AND OBJECT_SCHEMA_NAME(fk.referenced_object_id) <> N'seg';

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
-- COMMIT;
-- ROLLBACK;
