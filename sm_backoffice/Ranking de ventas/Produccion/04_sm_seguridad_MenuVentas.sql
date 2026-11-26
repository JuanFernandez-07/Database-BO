-- ════════════════════════════════════════════════════════════════════════════════════
-- PRODUCCIÓN · Paso 4 de 5 · Base: sm_seguridad
-- Menú "Ventas" con Resumen de Ventas (/ventas/resumen) y Ranking de Ventas (/ventas/ranking).
-- ════════════════════════════════════════════════════════════════════════════════════
-- CUÁNDO: justo DESPUÉS de publicar el frontend de smb_react con las rutas /ventas/*.
--   Si se corre antes, Resumen de Ventas desaparece para los usuarios hasta que se publique.
--
-- Qué hace (busca todo por nombre/path, porque los códigos en producción pueden ser distintos a dev):
--   1. Crea el menú "Ventas" si no existe (código = siguiente disponible).
--   2. Mueve el módulo Resumen de Ventas a ese menú y cambia su path a /ventas/resumen.
--      La FK de sct.seg_rmo_rol_modulo usa el par (menú, módulo): por eso las asignaciones a roles
--      se respaldan, se borran y se reinsertan con el menú nuevo (un UPDATE directo falla).
--   3. Crea el módulo Ranking de Ventas si no existe (código = siguiente disponible).
--   4. Asigna Ranking a los mismos roles y negocios que ya tienen Resumen de Ventas.
--      Si debe ir a otros roles, ajustar después desde Administración → Seguridad → Roles.
--
-- Corre en una transacción y NO confirma solo: revisar los SELECT de ANTES / DESPUÉS y ejecutar
-- COMMIT o ROLLBACK al final. No dejar la transacción abierta: bloquea las tablas de seguridad.

USE sm_seguridad;
GO
SET XACT_ABORT ON;

DECLARE @menuNombre   NVARCHAR(200) = N'Ventas';
DECLARE @pathResumenViejo NVARCHAR(200) = N'/resumen-ventas';
DECLARE @pathResumen  NVARCHAR(200) = N'/ventas/resumen';
DECLARE @pathRanking  NVARCHAR(200) = N'/ventas/ranking';

-- Módulo Resumen: por path viejo o, si ya se movió, por el nuevo.
DECLARE @modResumen INT = (SELECT mod_codigo FROM sct.seg_mod_modulo WHERE mod_path IN (@pathResumenViejo, @pathResumen));
IF @modResumen IS NULL
    THROW 50020, 'No se encontró el módulo Resumen de Ventas (/resumen-ventas ni /ventas/resumen).', 1;

-- Estado antes
SELECT 'ANTES' AS momento, * FROM sct.seg_mnu_menu   WHERE mnu_nombre = @menuNombre;
SELECT 'ANTES' AS momento, * FROM sct.seg_mod_modulo WHERE mod_path IN (@pathResumenViejo, @pathResumen, @pathRanking);
SELECT 'ANTES' AS momento, * FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod = @modResumen;

BEGIN TRAN;

    -- 1. Menú Ventas
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre)
        INSERT INTO sct.seg_mnu_menu (mnu_codigo, mnu_nombre, mnu_descripcion, mnu_estado, mnu_created_at, mnu_updated_at)
        SELECT ISNULL(MAX(mnu_codigo), 0) + 1, @menuNombre, N'Resumen y Ranking de Ventas', 1, GETDATE(), GETDATE()
        FROM sct.seg_mnu_menu;

    DECLARE @menuVentas INT = (SELECT mnu_codigo FROM sct.seg_mnu_menu WHERE mnu_nombre = @menuNombre);

    -- 2. Mover Resumen de Ventas (solo si todavía no está en el menú Ventas con el path nuevo)
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo
                   WHERE mod_codigo = @modResumen AND mod_mnu_codigo = @menuVentas AND mod_path = @pathResumen)
    BEGIN
        SELECT * INTO #rmo_resumen FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod = @modResumen;

        DELETE FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod = @modResumen;

        UPDATE sct.seg_mod_modulo
        SET mod_mnu_codigo = @menuVentas,
            mod_path       = @pathResumen,
            mod_updated_at = GETDATE()
        WHERE mod_codigo = @modResumen;

        INSERT INTO sct.seg_rmo_rol_modulo
            (rmo_codigo_neg, rmo_codigo_rol, rmo_codigo_mnu, rmo_codigo_mod, rmo_estado, rmo_created_at, rmo_updated_at)
        SELECT rmo_codigo_neg, rmo_codigo_rol, @menuVentas, rmo_codigo_mod, rmo_estado, rmo_created_at, GETDATE()
        FROM #rmo_resumen;
    END;

    -- 3. Módulo Ranking de Ventas
    IF NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo WHERE mod_path = @pathRanking)
    BEGIN
        DECLARE @modRankingNuevo INT = (SELECT ISNULL(MAX(mod_codigo), 0) + 1 FROM sct.seg_mod_modulo);

        INSERT INTO sct.seg_mod_modulo
            (mod_codigo, mod_mnu_codigo, mod_nombre, mod_descripcion, mod_path, mod_estado, mod_orden, mod_visible, mod_created_at, mod_updated_at)
        VALUES
            (@modRankingNuevo, @menuVentas, N'Ranking de Ventas', N'Ranking de tiendas por venta TY vs LY',
             @pathRanking, '1', CAST(@modRankingNuevo AS VARCHAR(10)), 1, GETDATE(), GETDATE());
    END;

    DECLARE @modRanking INT = (SELECT mod_codigo FROM sct.seg_mod_modulo WHERE mod_path = @pathRanking);

    -- 4. Ranking a los mismos roles/negocios que Resumen
    INSERT INTO sct.seg_rmo_rol_modulo
        (rmo_codigo_neg, rmo_codigo_rol, rmo_codigo_mnu, rmo_codigo_mod, rmo_estado, rmo_created_at, rmo_updated_at)
    SELECT r.rmo_codigo_neg, r.rmo_codigo_rol, @menuVentas, @modRanking, 1, GETDATE(), GETDATE()
    FROM sct.seg_rmo_rol_modulo r
    WHERE r.rmo_codigo_mod = @modResumen
      AND r.rmo_estado = 1
      AND NOT EXISTS (SELECT 1 FROM sct.seg_rmo_rol_modulo x
                      WHERE x.rmo_codigo_neg = r.rmo_codigo_neg
                        AND x.rmo_codigo_rol = r.rmo_codigo_rol
                        AND x.rmo_codigo_mod = @modRanking);

    -- Estado después: Resumen y Ranking en el menú Ventas, con las mismas asignaciones.
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mnu_menu   WHERE mnu_codigo = @menuVentas;
    SELECT 'DESPUES' AS momento, * FROM sct.seg_mod_modulo WHERE mod_codigo IN (@modResumen, @modRanking);
    SELECT 'DESPUES' AS momento, * FROM sct.seg_rmo_rol_modulo WHERE rmo_codigo_mod IN (@modResumen, @modRanking)
    ORDER BY rmo_codigo_mod, rmo_codigo_neg, rmo_codigo_rol;

-- Revisar los resultados y ejecutar UNA de estas dos líneas:
-- COMMIT;
-- ROLLBACK;
