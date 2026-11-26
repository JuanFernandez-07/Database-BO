-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_reportes ███
-- Conexión de tiendas · Paso 4: alta del reporte en el módulo de Reportes.
-- Requiere el paso 3 (dbo.usp_TLS_ReporteConexionTiendas en sm_pos). Idempotente.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Reporte "BOSLC: Conexión de tiendas", tipo_sql = 2 (declara los parámetros y ejecuta el SP).
-- Toma como base el reporte 100000 (BOSLC: Ejecución de Lectura de Cajas):
--   * r_reporte: misma estructura; cambian id, tipo, nombre, descripción, ejemplo y consulta.
--   * r_reporte_parametro: sus parámetros 1 y 2 (FechaIni y FechaFin, tipo fecha, por defecto hoy).
--   * r_reporte_rol: los mismos roles y negocios que ven la Lectura de Cajas.
-- Se copia con SELECT * para conservar las columnas de configuración que no usa este reporte.
-- Id: el siguiente libre del rango 100000-499999 (BOSLC). Si el reporte ya existe, conserva su id.

USE sm_reportes;
GO
SET XACT_ABORT ON;
GO

DECLARE @id_base    INT = 100000;
DECLARE @nombre     NVARCHAR(100) = N'BOSLC: Conexión de tiendas';
DECLARE @id_reporte INT = (SELECT id_reporte FROM rep.r_reporte WHERE id_sistema = 1000 AND nombre = @nombre);

IF NOT EXISTS (SELECT 1 FROM rep.r_reporte WHERE id_sistema = 1000 AND id_reporte = @id_base)
BEGIN
    RAISERROR(N'No existe el reporte base 100000. No se ejecutó nada.', 16, 1);
    RETURN;
END;

IF @id_reporte IS NULL
    SET @id_reporte = (SELECT MAX(id_reporte) + 1 FROM rep.r_reporte
                       WHERE id_sistema = 1000 AND id_reporte BETWEEN 100000 AND 499999);

BEGIN TRAN;

    -- Si ya existía, se vuelve a crear.
    DELETE FROM rep.r_reporte_rol       WHERE id_sistema = 1000 AND id_reporte = @id_reporte;
    DELETE FROM rep.r_reporte_parametro WHERE id_sistema = 1000 AND id_reporte = @id_reporte;
    DELETE FROM rep.r_reporte           WHERE id_sistema = 1000 AND id_reporte = @id_reporte;

    -- 1. Reporte
    SELECT * INTO #reporte FROM rep.r_reporte WHERE id_sistema = 1000 AND id_reporte = @id_base;
    UPDATE #reporte
    SET id_reporte   = @id_reporte,
        tipo_sql     = 2,
        nombre       = @nombre,
        descripcion  = N'Prueba de conexión Azure -> KIO -> tienda cada 3 horas: OK o ERROR con el motivo, por tienda y corrida.',
        valores      = N'''20261116'', ''20261117''',
        consulta_sql = N'begin exec [sm_pos].[dbo].[usp_TLS_ReporteConexionTiendas] @FechaIni, @FechaFin end';
    INSERT INTO rep.r_reporte SELECT * FROM #reporte;

    -- 2. Parámetros: Fecha Inicio y Fecha Fin
    SELECT * INTO #parametro FROM rep.r_reporte_parametro
    WHERE id_sistema = 1000 AND id_reporte = @id_base AND id_parametro IN (1, 2);
    UPDATE #parametro
    SET id_reporte  = @id_reporte,
        descripcion = CASE id_parametro WHEN 1 THEN N'Fecha inicial de las corridas'
                                        ELSE N'Fecha final de las corridas' END,
        valores     = CASE id_parametro WHEN 1 THEN N'20261116' ELSE N'20261117' END;
    INSERT INTO rep.r_reporte_parametro SELECT * FROM #parametro;

    -- 3. Roles y negocios: los mismos de la Lectura de Cajas
    SELECT * INTO #rol FROM rep.r_reporte_rol WHERE id_sistema = 1000 AND id_reporte = @id_base;
    UPDATE #rol SET id_reporte = @id_reporte;
    INSERT INTO rep.r_reporte_rol SELECT * FROM #rol;

COMMIT;

DROP TABLE #reporte, #parametro, #rol;

-- ─── Verificación ───────────────────────────────────────────────────────────────────
-- 1. Alta: 1 reporte, 2 parámetros de fecha y los roles del 100000.
SELECT id_reporte, tipo_sql, nombre, consulta_sql FROM rep.r_reporte WHERE id_sistema = 1000 AND id_reporte = @id_reporte;
SELECT id_parametro, nombre, etiqueta, tipo_dato FROM rep.r_reporte_parametro WHERE id_sistema = 1000 AND id_reporte = @id_reporte ORDER BY id_parametro;
SELECT * FROM rep.r_reporte_rol WHERE id_sistema = 1000 AND id_reporte = @id_reporte;

-- 2. La sentencia que arma el módulo y su resultado (lo mismo que hace la API al dar Buscar).
DECLARE @sentencia NVARCHAR(MAX);
EXEC rep.sp_r_reporte
    @pid_sistema    = 1000,
    @pid_reporte    = @id_reporte,
    @psentencia_sql = @sentencia OUTPUT,
    @pvalores       = N'''20261116'',''20261117''';
SELECT @sentencia AS sentencia;
EXEC (@sentencia);
GO
