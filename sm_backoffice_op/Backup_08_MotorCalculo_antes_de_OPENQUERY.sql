-- =============================================
-- Módulo: Motor de Cálculo (Factor SKU + Patrón Horario)
-- Funciones: fn_plh_FactoresSKU, fn_plh_PatronHorario
-- SPs: plh_mrf_CalcularMotorMes, plh_mrf_EliminarMotorMes
-- Base de datos: sm_backoffice_op
--
-- PROPUESTA v2: Unidades por bolsa
-- Si Unidad_Medida del ítem en la receta contiene un número antes de la U
-- (ej. BOL6U, BL12U, BO3U), el consumo se multiplica por ese número para
-- expresarlo en unidades individuales en lugar de bolsas.
-- Rollback: 08_MotorCalculo.sql
-- =============================================

USE [sm_backoffice_op];
GO

-- ─── Función: Factor SKU ─────────────────────────────────────────────────────
-- Factor_SKU = Consumo_SKU_Mes_Ref / (Venta_Neta_Total_Tienda_Mes_Ref / 1000)
-- Retorna el factor por SKU activo para la tienda en el mes de referencia.

CREATE OR ALTER FUNCTION [plh].[fn_plh_FactoresSKU]
(
    @TiendaCodigo     INT,
    @CodigoNeg        NVARCHAR(10),
    @AnioRef          INT,
    @MesRef           INT,
    -- CR-20260922-01 (HORNOS-F2-REF): tienda cuyo historial de ventas/consumo se usa en
    -- vez del propio (tiendas nuevas sin datos suficientes). NULL = comportamiento actual
    -- (usa su propio historial). El catálogo (qué productos vende) sigue siendo el de
    -- @TiendaCodigo siempre — @TiendaReferencia solo reemplaza la FUENTE del historial.
    @TiendaReferencia INT = NULL
)
RETURNS TABLE
AS
RETURN
(
    WITH
    Rango AS (
        SELECT
            DATEFROMPARTS(@AnioRef, @MesRef, 1)                    AS fecha_inicio,
            DATEADD(MONTH, 1, DATEFROMPARTS(@AnioRef, @MesRef, 1)) AS fecha_fin
    ),
    DataArea AS (
        SELECT n.neg_referencia1 AS data_area_id
        FROM plh.Vw_plh_neg_Negocios n
        WHERE CAST(n.neg_codigo AS NVARCHAR(20)) = @CodigoNeg
    ),
    RecetasExcluidas AS (
        SELECT rd.Id_Receta, rd.DataAreaId
        FROM plh.Receta_detalle rd
        GROUP BY rd.Id_Receta, rd.DataAreaId
        HAVING COUNT(*) = 1
           AND MAX(CASE WHEN rd.Codigo_Item = CAST(rd.Id_Receta AS VARCHAR(50)) THEN 1 ELSE 0 END) = 1
    ),
    VentasPorSku AS (
        SELECT
            cat.cat_pro_codigo AS pro_codigo,
            ISNULL(SUM(
                g.Cantidad
                * rd.Cantidad_Item
                -- Si Unidad_Medida termina en [dígito]U (ej. BOL6U, BL12U),
                -- extraemos el número para convertir bolsas → unidades individuales.
                * ISNULL(
                    CASE WHEN rd.Unidad_Medida LIKE '%[0-9]U'
                         THEN TRY_CAST(
                                SUBSTRING(
                                    rd.Unidad_Medida,
                                    PATINDEX('%[0-9]%', rd.Unidad_Medida),
                                    LEN(rd.Unidad_Medida) - PATINDEX('%[0-9]%', rd.Unidad_Medida)
                                ) AS INT)
                         ELSE 1
                    END, 1)
            ), 0) AS cantidad_sku
        FROM plh.plh_cat_catalogo_productos cat
        CROSS JOIN Rango r
        LEFT JOIN plh.Receta_detalle rd
            ON  rd.Codigo_Item = ISNULL(cat.cat_pro_sustituto_codigo, cat.cat_pro_codigo)
            AND rd.DataAreaId  = (SELECT data_area_id FROM DataArea)
            AND rd.Modificador <> 1
        LEFT JOIN RecetasExcluidas re
            ON  re.Id_Receta  = rd.Id_Receta
            AND re.DataAreaId = rd.DataAreaId
        LEFT JOIN plh.Vw_Vista_Consumo g
            ON  CAST(g.ITEM AS VARCHAR(50)) = CAST(rd.Id_Receta AS VARCHAR(50))
            AND g.LC_UNIT   = COALESCE(@TiendaReferencia, @TiendaCodigo)
            AND g.Cantidad  > 0
            AND g.LC_DOB   >= r.fecha_inicio
            AND g.LC_DOB    < r.fecha_fin
        WHERE cat.cat_codigo_neg    = @CodigoNeg
          AND cat.cat_tienda_codigo IN (0, @TiendaCodigo)
          AND cat.cat_activo        = 1
          AND re.Id_Receta          IS NULL
        GROUP BY cat.cat_pro_codigo
    ),
    VentaNeta AS (
        SELECT ISNULL(SUM(vd.venta_diaria), 0) AS total
        FROM plh.plh_Vw_VentaDiaria vd
        CROSS JOIN Rango r
        WHERE vd.tienda = COALESCE(@TiendaReferencia, @TiendaCodigo)
          AND vd.fecha >= r.fecha_inicio
          AND vd.fecha  < r.fecha_fin
    )
    SELECT
        v.pro_codigo,
        CAST(
            CASE WHEN t.total > 0
                 THEN v.cantidad_sku / (t.total / 1000.0)
                 ELSE 0
            END
        AS DECIMAL(18,6)) AS factor_sku
    FROM VentasPorSku v
    CROSS JOIN VentaNeta t
);
GO

-- ─── Función: Patrón Horario ─────────────────────────────────────────────────
-- Retorna % de ventas por día de semana (1=Lun…7=Dom) y hora (0-23).
-- Porcentaje = Ventas_Hora / Ventas_Dia

CREATE OR ALTER FUNCTION [plh].[fn_plh_PatronHorario]
(
    @TiendaCodigo     INT,
    @CodigoNeg        NVARCHAR(10),
    @AnioRef          INT,
    @MesRef           INT,
    -- CR-20260922-01 (HORNOS-F2-REF): ver fn_plh_FactoresSKU — mismo criterio.
    @TiendaReferencia INT = NULL
)
RETURNS TABLE
AS
RETURN
(
    WITH
    Rango AS (
        SELECT
            DATEFROMPARTS(@AnioRef, @MesRef, 1)                    AS fecha_inicio,
            DATEADD(MONTH, 1, DATEFROMPARTS(@AnioRef, @MesRef, 1)) AS fecha_fin
    ),
    DataArea AS (
        SELECT n.neg_referencia1 AS data_area_id
        FROM plh.Vw_plh_neg_Negocios n
        WHERE CAST(n.neg_codigo AS NVARCHAR(20)) = @CodigoNeg
    ),
    RecetasExcluidas AS (
        SELECT rd.Id_Receta, rd.DataAreaId
        FROM plh.Receta_detalle rd
        GROUP BY rd.Id_Receta, rd.DataAreaId
        HAVING COUNT(*) = 1
           AND MAX(CASE WHEN rd.Codigo_Item = CAST(rd.Id_Receta AS VARCHAR(50)) THEN 1 ELSE 0 END) = 1
    ),
    VentasBase AS (
        SELECT
            g.LC_DOB                AS fecha_neg,
            CAST(g.HOUR AS TINYINT) AS hora,
            SUM(g.Cantidad)         AS cantidad
        FROM plh.Vw_Vista_Consumo g
        INNER JOIN plh.Receta_detalle rd
            ON  CAST(rd.Id_Receta AS VARCHAR(50)) = CAST(g.ITEM AS VARCHAR(50))
            AND rd.DataAreaId  = (SELECT data_area_id FROM DataArea)
            AND rd.Modificador <> 1
        LEFT JOIN RecetasExcluidas re
            ON  re.Id_Receta  = rd.Id_Receta
            AND re.DataAreaId = rd.DataAreaId
        INNER JOIN plh.plh_cat_catalogo_productos cat
            ON  cat.cat_pro_codigo    = rd.Codigo_Item
            AND cat.cat_codigo_neg    = @CodigoNeg
            AND cat.cat_tienda_codigo IN (0, @TiendaCodigo)
            AND cat.cat_activo        = 1
        CROSS JOIN Rango r
        WHERE g.LC_UNIT   = COALESCE(@TiendaReferencia, @TiendaCodigo)
          AND g.Cantidad  > 0
          AND g.LC_DOB   >= r.fecha_inicio
          AND g.LC_DOB    < r.fecha_fin
          AND re.Id_Receta IS NULL
        GROUP BY g.LC_DOB, g.HOUR
    ),
    ConDiaSemana AS (
        SELECT
            CAST(
                CASE DATEPART(WEEKDAY, fecha_neg)
                    WHEN 1 THEN 7
                    ELSE DATEPART(WEEKDAY, fecha_neg) - 1
                END
            AS TINYINT) AS dia_semana,
            hora,
            cantidad
        FROM VentasBase
    ),
    VentasPorDiaHora AS (
        SELECT dia_semana, hora, SUM(cantidad) AS cantidad_hora
        FROM ConDiaSemana
        GROUP BY dia_semana, hora
    ),
    VentasPorDia AS (
        SELECT dia_semana, SUM(cantidad_hora) AS cantidad_dia
        FROM VentasPorDiaHora
        GROUP BY dia_semana
    )
    SELECT
        h.dia_semana,
        h.hora,
        CAST(
            CASE WHEN d.cantidad_dia > 0
                 THEN h.cantidad_hora / d.cantidad_dia
                 ELSE 0
            END
        AS DECIMAL(8,6)) AS porcentaje
    FROM VentasPorDiaHora h
    INNER JOIN VentasPorDia d ON d.dia_semana = h.dia_semana
);
GO

-- ─── SP: Calcular y persistir Motor del Mes ──────────────────────────────────
-- Inmutable: si ya existe para tienda+mes_proyectado → retorna error.

-- HOTFIX (16-sep-2026): fn_plh_FactoresSKU / fn_plh_PatronHorario leen
-- Vw_Vista_Consumo, que consulta el linked server de Aloha (OLEDB). Cuando
-- Aloha responde lento (o se queda sin responder), la versión anterior de
-- este SP mantenía BEGIN TRANSACTION abierto DESDE ANTES de esa espera —
-- así que sostenía bloqueos sobre plh_fct_factor_sku todo ese tiempo.
-- Resultado real en producción: 4 corridas de este SP quedaron esperando a
-- Aloha (wait_type=OLEDB) más de una hora, y sus bloqueos en cadena dejaron
-- congelados Generar Plan y Control para otras tiendas.
--
-- Fix: el cálculo que depende de Aloha corre ANTES de abrir la transacción,
-- a tablas temporales — si Aloha tarda o se cuelga, esa tienda se demora
-- sola, sin bloquear a nadie más. La transacción solo envuelve el MERGE
-- final (rápido, 100% local). Se revalida "¿ya existe?" otra vez ya dentro
-- de la transacción, para cerrar la condición de carrera de doble-clic que
-- antes podía dejar dos corridas escribiendo para la misma tienda/mes.

CREATE OR ALTER PROCEDURE [plh].[plh_mrf_CalcularMotorMes]
    @TiendaCodigo       INT,
    @CodigoNeg          NVARCHAR(10),
    @AnioProyectado     INT,
    @MesProyectado      INT,
    @AnioRef            INT,
    @MesRef             INT,
    @UsuarioCodigo      NVARCHAR(50),
    -- CR-20260922-01 (HORNOS-F2-REF): selección puntual del usuario al calcular (toggle +
    -- selector de tienda en el slide de "Calcular mes" del Motor de Cálculo) — no se
    -- persiste en ningún lado, viaja directo como parámetro desde el frontend.
    -- NULL = usa su propio historial (comportamiento actual).
    @TiendaReferencia   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM plh.plh_fct_factor_sku
        WHERE fct_tienda_codigo   = @TiendaCodigo
          AND fct_codigo_neg      = @CodigoNeg
          AND fct_anio_proyectado = @AnioProyectado
          AND fct_mes_proyectado  = @MesProyectado
    )
    BEGIN
        RAISERROR('Ya existe un cálculo para esta tienda y mes proyectado. No se permite recalcular.', 16, 1);
        RETURN;
    END

    -- Parte lenta / dependiente de Aloha — SIN transacción abierta.
    SELECT pro_codigo, factor_sku
    INTO #FactoresSku
    FROM plh.fn_plh_FactoresSKU(@TiendaCodigo, @CodigoNeg, @AnioRef, @MesRef, @TiendaReferencia);

    SELECT dia_semana, hora, porcentaje
    INTO #PatronHorario
    FROM plh.fn_plh_PatronHorario(@TiendaCodigo, @CodigoNeg, @AnioRef, @MesRef, @TiendaReferencia);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Revalidación dentro de la transacción: por si otra sesión terminó
        -- de calcular esto mientras esta esperaba a Aloha.
        IF EXISTS (
            SELECT 1 FROM plh.plh_fct_factor_sku
            WHERE fct_tienda_codigo   = @TiendaCodigo
              AND fct_codigo_neg      = @CodigoNeg
              AND fct_anio_proyectado = @AnioProyectado
              AND fct_mes_proyectado  = @MesProyectado
        )
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Ya existe un cálculo para esta tienda y mes proyectado. No se permite recalcular.', 16, 1);
            RETURN;
        END

        MERGE plh.plh_fct_factor_sku AS tgt
        USING #FactoresSku AS src
        ON  tgt.fct_tienda_codigo    = @TiendaCodigo
        AND tgt.fct_codigo_neg       = @CodigoNeg
        AND tgt.fct_pro_codigo       = src.pro_codigo
        AND tgt.fct_anio_proyectado  = @AnioProyectado
        AND tgt.fct_mes_proyectado   = @MesProyectado
        WHEN NOT MATCHED THEN
            INSERT (fct_codigo_neg, fct_tienda_codigo, fct_pro_codigo,
                    fct_anio_proyectado, fct_mes_proyectado,
                    fct_anio_referencia, fct_mes_referencia,
                    fct_factor_sku, fct_fecha_calculo, fct_usuario_calculo)
            VALUES (@CodigoNeg, @TiendaCodigo, src.pro_codigo,
                    @AnioProyectado, @MesProyectado,
                    @AnioRef, @MesRef,
                    src.factor_sku, GETDATE(), @UsuarioCodigo);

        MERGE plh.plh_pha_patron_horario AS tgt
        USING #PatronHorario AS src
        ON  tgt.pha_tienda_codigo    = @TiendaCodigo
        AND tgt.pha_codigo_neg       = @CodigoNeg
        AND tgt.pha_anio_proyectado  = @AnioProyectado
        AND tgt.pha_mes_proyectado   = @MesProyectado
        AND tgt.pha_dia_semana       = src.dia_semana
        AND tgt.pha_hora             = src.hora
        WHEN NOT MATCHED THEN
            INSERT (pha_codigo_neg, pha_tienda_codigo,
                    pha_anio_proyectado, pha_mes_proyectado,
                    pha_dia_semana, pha_hora, pha_porcentaje,
                    pha_fecha_calculo, pha_usuario_calculo)
            VALUES (@CodigoNeg, @TiendaCodigo,
                    @AnioProyectado, @MesProyectado,
                    src.dia_semana, src.hora, src.porcentaje,
                    GETDATE(), @UsuarioCodigo);

        COMMIT TRANSACTION;

        SELECT COUNT(*) AS factores_calculados
        FROM plh.plh_fct_factor_sku
        WHERE fct_tienda_codigo   = @TiendaCodigo
          AND fct_codigo_neg      = @CodigoNeg
          AND fct_anio_proyectado = @AnioProyectado
          AND fct_mes_proyectado  = @MesProyectado;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_mrf_EliminarMotorMes]
    @TiendaCodigo   INT,
    @CodigoNeg      NVARCHAR(10),
    @AnioProyectado INT,
    @MesProyectado  INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM plh.plh_fct_factor_sku
    WHERE fct_tienda_codigo   = @TiendaCodigo
      AND fct_codigo_neg      = @CodigoNeg
      AND fct_anio_proyectado = @AnioProyectado
      AND fct_mes_proyectado  = @MesProyectado;

    DELETE FROM plh.plh_pha_patron_horario
    WHERE pha_tienda_codigo   = @TiendaCodigo
      AND pha_codigo_neg      = @CodigoNeg
      AND pha_anio_proyectado = @AnioProyectado
      AND pha_mes_proyectado  = @MesProyectado;
END;
GO
