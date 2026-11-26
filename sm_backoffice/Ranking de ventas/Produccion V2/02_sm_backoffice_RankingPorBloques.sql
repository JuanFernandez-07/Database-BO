-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ El script 06 reemplaza las secciones 1 (bloque), 4 y 5 de este archivo. NO volver a correr este
--   archivo después del 06: regresaría los SPs a la versión sin relleno de bloques.
-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███   — NO en KIO
-- PRODUCCIÓN V2 · Paso 2 de 4 · Resumen por bloques de importación + importación única.
-- Requiere: paso 1 (jobs viejos borrados), Produccion/01 y Produccion/07 ya ejecutados, y el
-- 06 en KIO (SP_ObtenerVentaRankingGT/SV, no cambian).
-- Idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- QUÉ CAMBIA
--   * vta.rvt_rvd_resumen_venta_diaria guarda una FOTO por corrida (bloque): el acumulado del día a
--     esa hora, por tienda y categoría. Ya no se borra el día: cada corrida agrega su bloque.
--       rvd_actualizado_en = fecha y hora real de la importación.
--       rvd_bloque         = esa hora redondeada hacia abajo a 15 min (14:04 → 14:00). Con ella se
--                            compara contra el mismo bloque del año pasado.
--       rvd_ultimo_bloque  = 1 en las filas de la foto más reciente de cada (día, tienda).
--     Total del día = filas con rvd_ultimo_bloque = 1 (vista vta.vw_rvd_resumen_ultimo_bloque).
--     Incremento entre bloques = bloque actual - bloque anterior (consulta 7.3).
--   * Un solo SP llena la tabla: vta.rvd_ImportarVentaRanking (reemplaza a rvd_ImportarVentaDesdeKIO
--     y, para USA, al incremental de FiscalInvoice/RankingGNDSALE). Lo corre un solo job (paso 3).
--       GT / SV: igual que antes, por KIO tienda por tienda.
--       USA:     sm_pos.dbo.RankingGNDSALE, venta = AMOUNT del TYPE 52 (sin TYPEID 74 propina),
--                categoría por la caja = TYPEID2 del TYPE 44 del mismo check, misma regla que GT/SV.
--   * vta.vw_rvd_gndsale_neto (USA) también categoriza por caja: el LY de USA usa la misma regla.
--
-- QUÉ NO CAMBIA
--   * El LY sigue leyendo vta.vw_rvd_venta_neta (FiscalInvoice + RankingGNDSALE) hasta tener un año
--     de bloques. La importación de FiscalInvoice (sm_pos) debe seguir corriendo.
--
-- IMPORTANTE: NO volver a correr Produccion/01 ni Produccion/07 después de este script: regresan
-- vta.vw_rvd_gndsale_neto a la categoría por TYPEID y dejan SPs que borran el día completo.

USE sm_backoffice;
GO
SET XACT_ABORT ON;
GO

-- ─── 0. Verificaciones previas ──────────────────────────────────────────────────────
DECLARE @error NVARCHAR(400) =
    CASE
        WHEN OBJECT_ID('vta.rvt_rvd_resumen_venta_diaria', 'U') IS NULL
            THEN N'No existe vta.rvt_rvd_resumen_venta_diaria: correr antes Produccion/01.'
        WHEN OBJECT_ID('vta.rvd_FechaCorteKIO', 'IF') IS NULL
            THEN N'No existe vta.rvd_FechaCorteKIO: correr antes Produccion/07.'
        WHEN OBJECT_ID('vta.rvt_lik_log_importacion_kio', 'U') IS NULL
            THEN N'No existe vta.rvt_lik_log_importacion_kio: correr antes Produccion/07.'
        WHEN NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = N'10.138.58.142')
            THEN N'No existe el linked server [10.138.58.142] (KIO).'
        WHEN NOT EXISTS (SELECT 1 FROM sm_pos.INFORMATION_SCHEMA.COLUMNS
                         WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'RankingGNDSALE' AND COLUMN_NAME = 'TYPEID2')
            THEN N'sm_pos.dbo.RankingGNDSALE no tiene la columna TYPEID2 (caja del TYPE 44).'
        WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysjobs
                     WHERE name IN (N'sm_backoffice - Resumen venta diaria (incremental)',
                                    N'sm_backoffice - Ranking ventas GT/SV desde KIO'))
            THEN N'Los jobs anteriores siguen existiendo: correr antes el paso 1.'
    END;

IF @error IS NOT NULL
BEGIN
    RAISERROR(N'Verificación previa fallida: %s. No se ejecutó nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Funciones ───────────────────────────────────────────────────────────────────
-- Bloque de importación: la hora redondeada hacia abajo al intervalo del job (15 min).
-- Si el job cambia de intervalo, cambiar el 15 aquí (y solo aquí).
CREATE OR ALTER FUNCTION vta.rvd_BloqueImportacion (@momento DATETIME2(0))
RETURNS TABLE
AS
RETURN
    SELECT CAST(DATEADD(MINUTE, DATEDIFF(MINUTE, '20000101', @momento) / 15 * 15,
                        CAST('20000101' AS DATETIME2(0))) AS DATETIME2(0)) AS bloque;
GO

-- Categoría por caja (TermId en GT/SV, TYPEID2 del TYPE 44 en USA). Misma definición que
-- Produccion/07 y que el CASE de vta.vw_rvd_fiscal_invoice_neto (Produccion/01, solo histórico).
CREATE OR ALTER FUNCTION vta.rvd_CategoriaPorTerminal (@term_id INT)
RETURNS TABLE
AS
RETURN
    SELECT CASE
               WHEN @term_id BETWEEN 1 AND 5  THEN 'panaderia'
               WHEN @term_id BETWEEN 6 AND 15 THEN 'restaurante'
               ELSE 'otros'  -- Café (30-34), Delivery (35-36), Autoservicio (37-38) y cualquier otro
           END AS categoria;
GO

-- ─── 2. Tabla: columnas de bloque ───────────────────────────────────────────────────
IF COL_LENGTH('vta.rvt_rvd_resumen_venta_diaria', 'rvd_bloque') IS NULL
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria
        ADD rvd_bloque DATETIME2(0) NULL;
GO

IF COL_LENGTH('vta.rvt_rvd_resumen_venta_diaria', 'rvd_ultimo_bloque') IS NULL
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria
        ADD rvd_ultimo_bloque BIT NOT NULL
            CONSTRAINT DF_rvt_rvd_resumen_venta_diaria_ultimo_bloque DEFAULT (1);
GO

-- Filas anteriores a los bloques: cada (día, tienda) tenía una sola foto, que queda como su único
-- y último bloque (todas sus categorías se grabaron en el mismo INSERT, mismo rvd_actualizado_en).
UPDATE r
SET r.rvd_bloque = b.bloque
FROM vta.rvt_rvd_resumen_venta_diaria r
CROSS APPLY vta.rvd_BloqueImportacion(r.rvd_actualizado_en) b
WHERE r.rvd_bloque IS NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('vta.rvt_rvd_resumen_venta_diaria')
             AND name = 'rvd_bloque' AND is_nullable = 1)
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria ALTER COLUMN rvd_bloque DATETIME2(0) NOT NULL;
GO

-- PK: (día, tienda, bloque, categoría). Antes era (día, tienda, categoría).
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.object_id = OBJECT_ID('vta.rvt_rvd_resumen_venta_diaria')
      AND i.is_primary_key = 1
      AND c.name = 'rvd_bloque')
BEGIN
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria DROP CONSTRAINT PK_rvt_rvd_resumen_venta_diaria;
    ALTER TABLE vta.rvt_rvd_resumen_venta_diaria
        ADD CONSTRAINT PK_rvt_rvd_resumen_venta_diaria
            PRIMARY KEY (rvd_fecha, rvd_codigo_tie, rvd_bloque, rvd_categoria);
END;
GO

-- Lectura del total del día (pantalla, mes, año): solo las filas del último bloque.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rvt_rvd_resumen_venta_diaria_ultimo_bloque')
    CREATE INDEX IX_rvt_rvd_resumen_venta_diaria_ultimo_bloque
        ON vta.rvt_rvd_resumen_venta_diaria (rvd_fecha, rvd_codigo_tie, rvd_categoria)
        INCLUDE (rvd_venta_sin_iva, rvd_propina, rvd_bloque, rvd_actualizado_en)
        WHERE rvd_ultimo_bloque = 1;
GO

-- ─── 3. Vistas ──────────────────────────────────────────────────────────────────────
-- Total del día = última foto de cada (día, tienda). La pantalla lee el TY de aquí.
CREATE OR ALTER VIEW vta.vw_rvd_resumen_ultimo_bloque
AS
SELECT rvd_fecha, rvd_codigo_tie, rvd_categoria,
       rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
       rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_propina,
       rvd_bloque, rvd_actualizado_en
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_ultimo_bloque = 1;
GO

-- USA (reemplaza la de Produccion/01). Venta = TYPE 52 sin TYPEID 74 (propina); categoría por la
-- caja del check = TYPEID2 de su fila TYPE 44 (validado 28/10/2026: cada check tiene exactamente un
-- TYPE 44). Check sin TYPE 44 → caja NULL → 'otros'. La usan el LY (vía vw_rvd_venta_neta) y la
-- importación de USA.
CREATE OR ALTER VIEW vta.vw_rvd_gndsale_neto
AS
SELECT
    g.LC_UNIT AS tienda,
    g.LC_DOB  AS fecha,
    cat.categoria,
    0                         AS es_reembolso,
    -- Una fila por check y TYPEID: no se cuentan documentos aquí (la importación cuenta checks).
    0                         AS cuenta_venta,
    ISNULL(g.AMOUNT, 0)       AS venta_sin_iva,
    CAST(0 AS DECIMAL(18, 2)) AS iva,
    ISNULL(g.AMOUNT, 0)       AS venta_con_iva,
    CAST(0 AS DECIMAL(18, 2)) AS propina,  -- pendiente: la de US está en TYPEID 74 (excluido abajo)
    CAST(0 AS DECIMAL(18, 2)) AS monto_sin_iva_documento,
    -- Minutos desde la medianoche: LY hasta la hora actual cuando la fecha es hoy.
    g.CLOSEHOUR * 60 + g.CLOSEMIN AS minuto_del_dia,
    g.FechaImportacion,
    g.[CHECK]                 AS numero_check
FROM sm_pos.dbo.RankingGNDSALE g
OUTER APPLY (
    SELECT MAX(TRY_CONVERT(INT, c.TYPEID2)) AS caja
    FROM sm_pos.dbo.RankingGNDSALE c
    WHERE c.LC_UNIT = g.LC_UNIT
      AND c.LC_DOB  = g.LC_DOB
      AND c.[CHECK] = g.[CHECK]
      AND c.TYPE    = 44
) cj
CROSS APPLY vta.rvd_CategoriaPorTerminal(cj.caja) cat
WHERE g.TYPE = 52
  AND g.TYPEID <> 74;  -- Propina
GO

-- ─── 4. Grabar un bloque ────────────────────────────────────────────────────────────
-- Filas de un bloque: totales del día (acumulado a la hora de la corrida) por tienda y categoría.
IF TYPE_ID('vta.rvd_resumen_bloque') IS NULL
    CREATE TYPE vta.rvd_resumen_bloque AS TABLE (
        fecha               DATE           NOT NULL,
        tienda              INT            NOT NULL,
        categoria           VARCHAR(20)    NOT NULL,
        venta_sin_iva       DECIMAL(18, 2) NOT NULL,
        iva                 DECIMAL(18, 2) NOT NULL,
        venta_con_iva       DECIMAL(18, 2) NOT NULL,
        reembolso_sin_iva   DECIMAL(18, 2) NOT NULL,
        cantidad_ventas     INT            NOT NULL,
        cantidad_reembolsos INT            NOT NULL,
        propina             DECIMAL(18, 2) NOT NULL,
        PRIMARY KEY (fecha, tienda, categoria)
    );
GO

-- Interno: graba las filas recibidas como el bloque de la hora actual. Quien lo llama abre la
-- transacción y toma el bloqueo 'vta.rvt_rvd_resumen_venta_diaria'.
--   * Si ese (día, tienda) ya tiene el mismo bloque (dos corridas en el mismo cuarto de hora), lo
--     reemplaza: queda la foto más reciente.
--   * Las fotos anteriores del (día, tienda) dejan de ser el último bloque.
CREATE OR ALTER PROCEDURE vta.rvd_GuardarBloque
    @filas vta.rvd_resumen_bloque READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ahora  DATETIME2(0) = SYSDATETIME();
    DECLARE @bloque DATETIME2(0) = (SELECT bloque FROM vta.rvd_BloqueImportacion(@ahora));

    DELETE r
    FROM vta.rvt_rvd_resumen_venta_diaria r
    WHERE r.rvd_bloque = @bloque
      AND EXISTS (SELECT 1 FROM @filas f WHERE f.fecha = r.rvd_fecha AND f.tienda = r.rvd_codigo_tie);

    UPDATE r
    SET r.rvd_ultimo_bloque = 0
    FROM vta.rvt_rvd_resumen_venta_diaria r
    WHERE r.rvd_ultimo_bloque = 1
      AND EXISTS (SELECT 1 FROM @filas f WHERE f.fecha = r.rvd_fecha AND f.tienda = r.rvd_codigo_tie);

    INSERT INTO vta.rvt_rvd_resumen_venta_diaria (
        rvd_fecha, rvd_codigo_tie, rvd_categoria,
        rvd_venta_sin_iva, rvd_iva, rvd_venta_con_iva, rvd_reembolso_sin_iva,
        rvd_cantidad_ventas, rvd_cantidad_reembolsos, rvd_actualizado_en, rvd_propina,
        rvd_bloque, rvd_ultimo_bloque)
    SELECT f.fecha, f.tienda, f.categoria,
           f.venta_sin_iva, f.iva, f.venta_con_iva, f.reembolso_sin_iva,
           f.cantidad_ventas, f.cantidad_reembolsos, @ahora, f.propina,
           @bloque, 1
    FROM @filas f;
END;
GO

-- ─── 5. Importación única ───────────────────────────────────────────────────────────
-- Trae la venta del día de todas las tiendas y graba un bloque por tienda:
--   1. GT / SV: por KIO, tienda por tienda (mismas reglas que Produccion/07, documentación 3.10).
--   2. USA: sm_pos.dbo.RankingGNDSALE (vta.vw_rvd_gndsale_neto), todas las tiendas en una consulta.
-- Cada parte tiene su propio manejo de errores: si una tienda o USA falla, lo demás sigue.
-- Bitácora en vta.rvt_lik_log_importacion_kio (una fila por tienda, también USA).
-- GT/SV antes de la fecha de corte KIO no se tocan (ese histórico salió de FiscalInvoice); USA sí
-- se puede reprocesar en cualquier fecha.
CREATE OR ALTER PROCEDURE vta.rvd_ImportarVentaRanking
    @fecha          CHAR(8) = NULL,  -- YYYYMMDD; NULL = hoy
    @tienda_filtro  INT     = NULL,  -- código Aloha; NULL = todas
    @negocio_filtro INT     = NULL   -- 1 = GT, 2 = SV, 3 = USA; NULL = todos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ejecucion DATETIME2(0) = SYSDATETIME();
    IF @fecha IS NULL
        SET @fecha = CONVERT(CHAR(8), GETDATE(), 112);
    DECLARE @fecha_dia DATE = CONVERT(DATE, @fecha, 112);

    DECLARE @antes_del_corte BIT =
        CASE WHEN @fecha_dia < (SELECT fecha_corte FROM vta.rvd_FechaCorteKIO()) THEN 1 ELSE 0 END;

    IF @antes_del_corte = 1 AND @negocio_filtro IN (1, 2)
        THROW 50001, 'La fecha es anterior a la fecha de corte KIO: la venta de GT/SV de ese día salió de FiscalInvoice.', 1;

    DECLARE @filas vta.rvd_resumen_bloque;
    DECLARE @lock INT;

    -- ═══ 5.1 GT / SV por KIO ═══
    DROP TABLE IF EXISTS #tiendas;
    CREATE TABLE #tiendas (
        id         INT IDENTITY(1, 1) PRIMARY KEY,
        tienda     INT           NOT NULL,
        ip         NVARCHAR(128) NOT NULL,
        codigo_neg INT           NOT NULL
    );

    IF @antes_del_corte = 0 AND (@negocio_filtro IS NULL OR @negocio_filtro IN (1, 2))
        INSERT INTO #tiendas (tienda, ip, codigo_neg)
        SELECT TRY_CONVERT(INT, t.tie_codigo_aloha), LTRIM(RTRIM(t.tie_ip)) + N'\SQLEXPRESS', t.tie_codigo_neg
        FROM [10.138.58.142].[sm_pos].[dbo].[aloha_tie_tienda] t WITH (NOLOCK)
        WHERE t.tie_ip IS NOT NULL AND LTRIM(RTRIM(t.tie_ip)) <> ''
          AND t.tie_estado = 1
          AND t.tie_importar_venta = 1
          AND t.tie_codigo_neg IN (1, 2)
          AND TRY_CONVERT(INT, t.tie_codigo_aloha) IS NOT NULL
          AND (@negocio_filtro IS NULL OR t.tie_codigo_neg = @negocio_filtro)
          AND (@tienda_filtro IS NULL OR TRY_CONVERT(INT, t.tie_codigo_aloha) = @tienda_filtro);

    -- Lo que devuelve cada SP de KIO (mismo orden y tipos que su WITH RESULT SETS).
    CREATE TABLE #stg_gt (
        DocTypeId      NVARCHAR(5),
        TermId         INT,
        DateOfBusiness DATETIME,
        CheckNumber    INT,
        TaxableAmount  DECIMAL(18, 4),
        TotalTax       DECIMAL(18, 4),
        TotalTxn       DECIMAL(18, 4),
        PropinaCheck   DECIMAL(18, 4),
        SysDate        DATETIME,
        GUID           NVARCHAR(50)
    );

    CREATE TABLE #stg_sv (
        DocTypeId         NVARCHAR(5),
        TermId            INT,
        DateOfBusiness    DATETIME,
        CheckNumber       INT,
        VentaNeta         DECIMAL(18, 4),
        VentaTotal        DECIMAL(18, 4),
        TenderTip         DECIMAL(18, 4),
        SysDate           DATETIME,
        GUID              NVARCHAR(50),
        OriginalInvoiceNo NVARCHAR(50)
    );

    -- Documentos normalizados (mismas columnas para ambos países), con signo ya aplicado.
    CREATE TABLE #documentos (
        categoria         VARCHAR(20)    NOT NULL,
        es_reembolso      INT            NOT NULL,
        cuenta_venta      INT            NOT NULL,
        venta_sin_iva     DECIMAL(18, 6) NOT NULL,
        iva               DECIMAL(18, 6) NOT NULL,
        venta_con_iva     DECIMAL(18, 6) NOT NULL,
        propina           DECIMAL(18, 6) NOT NULL,
        reembolso_sin_iva DECIMAL(18, 6) NOT NULL   -- en positivo
    );

    DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM #tiendas);
    DECLARE @tienda INT, @ip NVARCHAR(128), @neg INT;
    DECLARE @sql NVARCHAR(MAX), @sqlKio NVARCHAR(MAX);
    DECLARE @t0 DATETIME2, @estado VARCHAR(20), @mensaje NVARCHAR(4000), @leidos INT;

    WHILE @i <= @max
    BEGIN
        SELECT @tienda = tienda, @ip = ip, @neg = codigo_neg FROM #tiendas WHERE id = @i;
        SELECT @t0 = SYSDATETIME(), @estado = NULL, @mensaje = NULL, @leidos = 0;

        BEGIN TRY
            TRUNCATE TABLE #stg_gt;
            TRUNCATE TABLE #stg_sv;
            TRUNCATE TABLE #documentos;
            DELETE FROM @filas;

            IF @neg = 1
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingGT] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [DocTypeId] nvarchar(5), [TermId] int, [DateOfBusiness] datetime, [CheckNumber] int,
                    [TaxableAmount] decimal(18, 4), [TotalTax] decimal(18, 4), [TotalTxn] decimal(18, 4),
                    [PropinaCheck] decimal(18, 4), [SysDate] datetime, [GUID] nvarchar(50)
                ))';
                SET @sql = N'INSERT INTO #stg_gt SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;

                -- La propina viene por check: se reparte entre los documentos del mismo check y tipo
                -- según su TotalTxn. En un reembolso (10) GNDITEM la trae negativa y sus montos vienen
                -- en positivo: se usa su valor absoluto y el signo lo aplica el reembolso, igual que Aloha.
                INSERT INTO #documentos
                SELECT c.categoria,
                       CASE WHEN g.tipo = '10' THEN 1 ELSE 0 END,
                       CASE WHEN g.tipo = '1'  THEN 1 ELSE 0 END,
                       s.signo * g.TaxableAmount * f.factor,
                       s.signo * g.TotalTax * f.factor,
                       s.signo * (g.TotalTxn - g.propina),
                       s.signo * g.propina,
                       CASE WHEN g.tipo = '10' THEN g.TaxableAmount * f.factor ELSE 0 END
                FROM (
                    SELECT x.*,
                           CASE WHEN x.PropinaCheck <> 0 THEN
                                    CASE WHEN x.tipo = '10' THEN ABS(x.PropinaCheck) ELSE x.PropinaCheck END *
                                    CASE WHEN SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo) = 0
                                         THEN 1.0 / COUNT(*) OVER (PARTITION BY x.CheckNumber, x.tipo)
                                         ELSE x.TotalTxn / SUM(x.TotalTxn) OVER (PARTITION BY x.CheckNumber, x.tipo)
                                    END
                                ELSE 0
                           END AS propina
                    FROM (
                        SELECT st.TermId, st.CheckNumber,
                               ISNULL(st.TaxableAmount, 0) AS TaxableAmount,
                               ISNULL(st.TotalTax, 0)      AS TotalTax,
                               ISNULL(st.TotalTxn, 0)      AS TotalTxn,
                               ISNULL(st.PropinaCheck, 0)  AS PropinaCheck,
                               LTRIM(RTRIM(st.DocTypeId))  AS tipo
                        FROM #stg_gt st
                    ) x
                    WHERE x.tipo IN ('1', '10')
                ) g
                CROSS APPLY (SELECT CASE WHEN g.tipo = '10' THEN -1 ELSE 1 END AS signo) s
                CROSS APPLY (SELECT CASE WHEN g.TotalTxn = 0 THEN 1
                                         ELSE (g.TotalTxn - g.propina) / g.TotalTxn END AS factor) f
                CROSS APPLY vta.rvd_CategoriaPorTerminal(g.TermId) c;
            END
            ELSE
            BEGIN
                SET @sqlKio = N'EXEC [sm_pos].[dbo].[SP_ObtenerVentaRankingSV] ''''' + @ip + N''''', ''''' + @fecha + N'''''
                WITH RESULT SETS ((
                    [DocTypeId] nvarchar(5), [TermId] int, [DateOfBusiness] datetime, [CheckNumber] int,
                    [VentaNeta] decimal(18, 4), [VentaTotal] decimal(18, 4), [TenderTip] decimal(18, 4),
                    [SysDate] datetime, [GUID] nvarchar(50), [OriginalInvoiceNo] nvarchar(50)
                ))';
                SET @sql = N'INSERT INTO #stg_sv SELECT * FROM OPENQUERY([10.138.58.142], ''' + @sqlKio + N''');';
                EXEC sp_executesql @sql;

                -- 05 (anulación) ya viene negativo: se suma tal cual y cuenta como reembolso.
                INSERT INTO #documentos
                SELECT c.categoria,
                       CASE WHEN x.tipo = '05' THEN 1 ELSE 0 END,
                       CASE WHEN x.tipo IN ('01', '03') THEN 1 ELSE 0 END,
                       x.VentaNeta,
                       x.VentaTotal - x.TenderTip - x.VentaNeta,
                       x.VentaTotal - x.TenderTip,
                       x.TenderTip,
                       CASE WHEN x.tipo = '05' THEN -x.VentaNeta ELSE 0 END
                FROM (
                    SELECT st.TermId,
                           ISNULL(st.VentaNeta, 0)    AS VentaNeta,
                           ISNULL(st.VentaTotal, 0)   AS VentaTotal,
                           ISNULL(st.TenderTip, 0)    AS TenderTip,
                           LTRIM(RTRIM(st.DocTypeId)) AS tipo
                    FROM #stg_sv st
                ) x
                CROSS APPLY vta.rvd_CategoriaPorTerminal(x.TermId) c
                WHERE x.tipo IN ('01', '03', '05');
            END;

            SET @leidos = (SELECT COUNT(*) FROM #documentos);

            IF @leidos = 0
                SET @estado = 'SIN_DATOS';  -- no se graba bloque: queda la última foto buena
            ELSE
            BEGIN
                INSERT INTO @filas (
                    fecha, tienda, categoria, venta_sin_iva, iva, venta_con_iva, reembolso_sin_iva,
                    cantidad_ventas, cantidad_reembolsos, propina)
                SELECT @fecha_dia, @tienda, categoria,
                       SUM(venta_sin_iva), SUM(iva), SUM(venta_con_iva), SUM(reembolso_sin_iva),
                       SUM(cuenta_venta), SUM(es_reembolso), SUM(propina)
                FROM #documentos
                GROUP BY categoria;

                BEGIN TRAN;
                    EXEC @lock = sp_getapplock
                        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
                        @LockOwner = N'Transaction', @LockTimeout = 60000;
                    IF @lock < 0
                        THROW 50002, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

                    EXEC vta.rvd_GuardarBloque @filas = @filas;
                COMMIT;

                SET @estado = 'OK';
            END;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;
            SELECT @estado = 'ERROR', @mensaje = ERROR_MESSAGE();
        END CATCH;

        INSERT INTO vta.rvt_lik_log_importacion_kio (
            lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
            lik_documentos_leidos, lik_segundos, lik_mensaje)
        VALUES (
            @ejecucion, @fecha_dia, @tienda, @estado,
            @leidos, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, @mensaje);

        SET @i += 1;
    END;

    -- ═══ 5.2 USA desde RankingGNDSALE ═══
    -- Tiendas = las que tienen venta ese día en RankingGNDSALE. Documentos leídos = checks.
    IF @negocio_filtro IS NULL OR @negocio_filtro = 3
    BEGIN
        SELECT @t0 = SYSDATETIME(), @mensaje = NULL;
        DELETE FROM @filas;

        BEGIN TRY
            INSERT INTO @filas (
                fecha, tienda, categoria, venta_sin_iva, iva, venta_con_iva, reembolso_sin_iva,
                cantidad_ventas, cantidad_reembolsos, propina)
            SELECT @fecha_dia, v.tienda, v.categoria,
                   SUM(v.venta_sin_iva), SUM(v.iva), SUM(v.venta_con_iva), 0,
                   COUNT(DISTINCT v.numero_check), 0, SUM(v.propina)
            FROM vta.vw_rvd_gndsale_neto v
            WHERE v.fecha = @fecha_dia
              AND (@tienda_filtro IS NULL OR v.tienda = @tienda_filtro)
            GROUP BY v.tienda, v.categoria;

            IF EXISTS (SELECT 1 FROM @filas)
            BEGIN
                BEGIN TRAN;
                    EXEC @lock = sp_getapplock
                        @Resource = N'vta.rvt_rvd_resumen_venta_diaria', @LockMode = N'Exclusive',
                        @LockOwner = N'Transaction', @LockTimeout = 60000;
                    IF @lock < 0
                        THROW 50002, 'No se obtuvo el bloqueo del resumen de venta diaria.', 1;

                    EXEC vta.rvd_GuardarBloque @filas = @filas;
                COMMIT;
            END;

            INSERT INTO vta.rvt_lik_log_importacion_kio (
                lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
                lik_documentos_leidos, lik_segundos, lik_mensaje)
            SELECT @ejecucion, @fecha_dia, tienda, 'OK',
                   SUM(cantidad_ventas), DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, N'USA (RankingGNDSALE)'
            FROM @filas
            GROUP BY tienda;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;

            -- Tienda 0 = toda la parte de USA (no se llegó a grabar ninguna tienda).
            INSERT INTO vta.rvt_lik_log_importacion_kio (
                lik_ejecucion, lik_fecha_negocio, lik_codigo_tie, lik_estado,
                lik_documentos_leidos, lik_segundos, lik_mensaje)
            VALUES (
                @ejecucion, @fecha_dia, 0, 'ERROR',
                0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0, N'USA: ' + ERROR_MESSAGE());
        END CATCH;
    END;
END;
GO

-- ─── 6. Permisos de la API ──────────────────────────────────────────────────────────
-- ANTES DE EJECUTAR esta sección: reemplazar <USUARIO_API_RANKING> por el usuario de
-- SmBackofficeRankingVentasConnection (el mismo de Produccion/02).
-- GRANT SELECT ON vta.vw_rvd_resumen_ultimo_bloque TO [<USUARIO_API_RANKING>];
GO

SET NOEXEC OFF;
GO

-- ════════════════════════════════════════════════════════════════════════════════════
-- 7. Pruebas y revisión (AZURE, sm_backoffice) — correr a mano, en este orden
-- ════════════════════════════════════════════════════════════════════════════════════
/*
-- 7.1 Una tienda de cada país (graba un bloque de hoy para cada una).
EXEC vta.rvd_ImportarVentaRanking @tienda_filtro = 134;               -- GT
EXEC vta.rvd_ImportarVentaRanking @tienda_filtro = 503151;            -- SV
EXEC vta.rvd_ImportarVentaRanking @negocio_filtro = 3;                -- USA (todas)

-- 7.2 Bitácora de esa corrida (OK / SIN_DATOS / ERROR).
SELECT lik_codigo_tie, lik_estado, lik_documentos_leidos, lik_segundos, lik_mensaje
FROM vta.rvt_lik_log_importacion_kio
WHERE lik_ejecucion >= DATEADD(MINUTE, -30, SYSDATETIME())
ORDER BY lik_ejecucion DESC, lik_codigo_tie;

-- 7.3 Bloques de hoy de una tienda: acumulado e incremento contra el bloque anterior.
SELECT rvd_bloque, rvd_actualizado_en, rvd_categoria, rvd_venta_sin_iva, rvd_propina,
       rvd_venta_sin_iva - LAG(rvd_venta_sin_iva) OVER (PARTITION BY rvd_categoria ORDER BY rvd_bloque) AS incremento,
       rvd_ultimo_bloque
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_fecha = CAST(GETDATE() AS DATE) AND rvd_codigo_tie = 134
ORDER BY rvd_categoria, rvd_bloque;

-- 7.4 Integridad: cada (día, tienda) debe tener un solo bloque marcado como último. 0 filas.
SELECT rvd_fecha, rvd_codigo_tie, COUNT(DISTINCT rvd_bloque) AS bloques_ultimos
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_ultimo_bloque = 1
GROUP BY rvd_fecha, rvd_codigo_tie
HAVING COUNT(DISTINCT rvd_bloque) > 1;

-- 7.5 USA: el total del día no cambia con la categoría por caja (solo se reparte distinto).
--     Ambas columnas iguales por tienda.
SELECT u.tienda, u.venta_gndsale, r.venta_resumen
FROM (SELECT LC_UNIT AS tienda, SUM(AMOUNT) AS venta_gndsale
      FROM sm_pos.dbo.RankingGNDSALE
      WHERE LC_DOB = CAST(GETDATE() AS DATE) AND TYPE = 52 AND TYPEID <> 74
      GROUP BY LC_UNIT) u
LEFT JOIN (SELECT rvd_codigo_tie, SUM(rvd_venta_sin_iva) AS venta_resumen
           FROM vta.vw_rvd_resumen_ultimo_bloque
           WHERE rvd_fecha = CAST(GETDATE() AS DATE)
           GROUP BY rvd_codigo_tie) r ON r.rvd_codigo_tie = u.tienda
ORDER BY u.tienda;

-- 7.6 USA por caja y categoría (cajas 1-5 Panadería, 6-15 Restaurante, resto Otros).
SELECT tienda, categoria, SUM(venta_sin_iva) AS venta, COUNT(DISTINCT numero_check) AS checks
FROM vta.vw_rvd_gndsale_neto
WHERE fecha = CAST(GETDATE() - 1 AS DATE)
GROUP BY tienda, categoria
ORDER BY tienda, categoria;

-- 7.7 (UNA VEZ, opcional) Reclasificar por caja los días anteriores de USA. Agrega un bloque nuevo
--     (el de la hora en que se corre) a cada día; el total del día no cambia, solo la categoría.
DECLARE @dia DATE, @dia_txt CHAR(8);
DECLARE dias CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT CONVERT(DATE, LC_DOB) FROM sm_pos.dbo.RankingGNDSALE
    WHERE LC_DOB < CAST(GETDATE() AS DATE) ORDER BY 1;
OPEN dias;
FETCH NEXT FROM dias INTO @dia;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @dia_txt = CONVERT(CHAR(8), @dia, 112);
    EXEC vta.rvd_ImportarVentaRanking @fecha = @dia_txt, @negocio_filtro = 3;
    FETCH NEXT FROM dias INTO @dia;
END;
CLOSE dias;
DEALLOCATE dias;

-- 7.8 Volumen de la tabla (≈ tiendas × categorías × 96 bloques por día).
SELECT rvd_fecha, COUNT(*) AS filas, COUNT(DISTINCT rvd_bloque) AS bloques
FROM vta.rvt_rvd_resumen_venta_diaria
WHERE rvd_fecha >= DATEADD(DAY, -3, CAST(GETDATE() AS DATE))
GROUP BY rvd_fecha
ORDER BY rvd_fecha;
*/
