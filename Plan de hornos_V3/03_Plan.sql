-- =============================================
-- Módulo: Plan de Hornos (APH)
-- SPs: plh_pla_GenerarPlan, plh_pla_ActualizarDetalle,
--      plh_pla_ActualizarPlanHorneada, plh_pla_ActualizarEstadoPlan,
--      plh_pld_ActualizarTotalHornear
-- Base de datos: sm_backoffice_op
-- Estados pla_estado: 0=BORRADOR, 1=ACTIVO, 2=CERRADO
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_pla_GenerarPlan]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @Fecha                  DATE,
    @FechaComparacion       DATE = NULL,
    @UsuarioCodigo          NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        IF EXISTS (
            SELECT 1 FROM plh.plh_pla_planes
            WHERE pla_codigo_neg    = @CodigoNeg
              AND pla_tienda_codigo = @TiendaCodigo
              AND pla_fecha         = @Fecha
        )
        BEGIN
            RAISERROR('Ya existe un plan generado para esta fecha y tienda.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM plh.plh_hor_horneadas
            WHERE hor_codigo_neg       = @CodigoNeg
              AND hor_tienda_codigo    = @TiendaCodigo
              AND hor_activa           = 1
              AND hor_es_extraordinaria = 0
        )
        BEGIN
            RAISERROR('No existen horneadas activas configuradas para esta tienda.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM plh.plh_cat_catalogo_productos
            WHERE cat_codigo_neg    = @CodigoNeg
              AND (cat_tienda_codigo = @TiendaCodigo OR cat_tienda_codigo = 0)
              AND cat_activo        = 1
        )
        BEGIN
            RAISERROR('No existen productos activos en el catálogo de hornos para esta tienda.', 16, 1);
            RETURN;
        END

        DECLARE @VentaProyectada DECIMAL(18,4) = 0;

        SELECT @VentaProyectada = ISNULL(vp.venta_proyectada, 0)
        FROM plh.Vw_Vista_Venta_proyectada vp
        INNER JOIN plh.Vw_plh_neg_Negocios n
            ON  n.neg_alias                       = vp.negocio
            AND CAST(n.neg_codigo AS NVARCHAR(20)) = @CodigoNeg
        WHERE vp.tienda = @TiendaCodigo
          AND vp.fecha  = @Fecha;

        DECLARE @DiaSemanaPlh TINYINT =
            CASE DATEPART(WEEKDAY, @Fecha)
                WHEN 1 THEN 7
                ELSE CAST(DATEPART(WEEKDAY, @Fecha) - 1 AS TINYINT)
            END;

        INSERT INTO plh.plh_pla_planes (
            pla_codigo_neg, pla_tienda_codigo, pla_fecha,
            pla_fecha_comparacion, pla_estado,
            pla_fecha_generacion, pla_usuario_generacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @Fecha,
            @FechaComparacion, 0,
            GETDATE(), @UsuarioCodigo
        );

        INSERT INTO plh.plh_pld_plan_detalle (
            pld_codigo_neg, pld_tienda_codigo, pld_fecha, pld_pro_codigo,
            pld_inventario_inicial, pld_proyectado_vender,
            pld_venta_hoy, pld_total_hornear
        )
        SELECT
            @CodigoNeg,
            @TiendaCodigo,
            @Fecha,
            cat.cat_pro_codigo,
            0,
            CASE
                WHEN @VentaProyectada > 0 AND f.fct_factor_sku > 0
                THEN CAST(@VentaProyectada * f.fct_factor_sku / 1000.0 AS DECIMAL(18,4))
                ELSE 0
            END,
            0,
            0
        FROM plh.plh_cat_catalogo_productos cat
        LEFT JOIN plh.plh_fct_factor_sku f
            ON  f.fct_pro_codigo       = cat.cat_pro_codigo
            AND f.fct_tienda_codigo    = @TiendaCodigo
            AND f.fct_codigo_neg       = @CodigoNeg
            AND f.fct_anio_proyectado  = YEAR(@Fecha)
            AND f.fct_mes_proyectado   = MONTH(@Fecha)
        WHERE cat.cat_codigo_neg      = @CodigoNeg
          AND (cat.cat_tienda_codigo  = @TiendaCodigo OR cat.cat_tienda_codigo = 0)
          AND cat.cat_activo          = 1;

        -- Reparto por ventanas de venta SECUENCIALES (sin traslape): la horneada N cubre
        -- la venta desde SU PROPIA hora_fin hasta la hora_fin de la SIGUIENTE horneada
        -- estándar (es cuando su pan deja de ser "lo único disponible" porque ya salió la
        -- siguiente tanda). La última horneada estándar del día no repite ciclo hacia el
        -- día siguiente: absorbe como remanente exacto lo que falte para que
        -- SUM(plh_proyeccion) = pld_proyectado_vender. Como estas ventanas NUNCA se
        -- traslapan entre sí (cada una empieza justo donde termina la anterior), el
        -- remanente de la última jamás puede ser negativo. Las horneadas "solo productos
        -- directos" quedan excluidas por completo (plh_proyeccion siempre 0).
        ;WITH HorneadasOrdenadas AS (
            SELECT
                h.hor_numero_secuencia,
                h.hor_hora_fin,
                LEAD(h.hor_hora_fin) OVER (ORDER BY h.hor_hora_fin) AS siguiente_hora_fin
            FROM plh.plh_hor_horneadas h
            WHERE h.hor_codigo_neg              = @CodigoNeg
              AND h.hor_tienda_codigo           = @TiendaCodigo
              AND h.hor_activa                  = 1
              AND h.hor_solo_productos_directos = 0
              AND h.hor_es_extraordinaria       = 0
        ),
        TodasHorneadas AS (
            SELECT h.hor_numero_secuencia, h.hor_solo_productos_directos
            FROM plh.plh_hor_horneadas h
            WHERE h.hor_codigo_neg        = @CodigoNeg
              AND h.hor_tienda_codigo     = @TiendaCodigo
              AND h.hor_activa            = 1
              AND h.hor_es_extraordinaria = 0
        )
        INSERT INTO plh.plh_plh_plan_horneada (
            plh_codigo_neg, plh_tienda_codigo, plh_fecha, plh_pro_codigo, plh_hor_numero_secuencia,
            plh_proyeccion, plh_pedido_chef, plh_cantidad_hornear,
            plh_fecha_actualizacion, plh_usuario_actualizacion_codigo
        )
        SELECT
            d.pld_codigo_neg,
            d.pld_tienda_codigo,
            d.pld_fecha,
            d.pld_pro_codigo,
            th.hor_numero_secuencia,
            CASE
                WHEN th.hor_solo_productos_directos = 1 THEN CAST(0 AS DECIMAL(18,4))
                -- Última horneada estándar (sin "siguiente"): se calcula abajo como remanente exacto
                WHEN ho.siguiente_hora_fin IS NULL THEN CAST(0 AS DECIMAL(18,4))
                ELSE CAST(
                    d.pld_proyectado_vender *
                    ISNULL((
                        SELECT SUM(pha.pha_porcentaje)
                        FROM plh.plh_pha_patron_horario pha
                        WHERE pha.pha_tienda_codigo   = @TiendaCodigo
                          AND pha.pha_codigo_neg      = @CodigoNeg
                          AND pha.pha_anio_proyectado = YEAR(@Fecha)
                          AND pha.pha_mes_proyectado  = MONTH(@Fecha)
                          AND pha.pha_dia_semana      = @DiaSemanaPlh
                          AND pha.pha_hora >= DATEPART(HOUR, ho.hor_hora_fin)
                          AND pha.pha_hora <  DATEPART(HOUR, ho.siguiente_hora_fin)
                    ), 0)
                AS DECIMAL(18,4))
            END,
            0,
            0,
            GETDATE(),
            @UsuarioCodigo
        FROM plh.plh_pld_plan_detalle d
        CROSS JOIN TodasHorneadas th
        LEFT JOIN HorneadasOrdenadas ho
            ON  ho.hor_numero_secuencia = th.hor_numero_secuencia
        WHERE d.pld_codigo_neg    = @CodigoNeg
          AND d.pld_tienda_codigo = @TiendaCodigo
          AND d.pld_fecha         = @Fecha;

        -- La última horneada estándar (mayor hora_fin, sin "siguiente") absorbe el
        -- remanente exacto: target - SUM(lo ya repartido a las demás). Como esas ventanas
        -- nunca se traslapan (ver arriba), este remanente siempre es >= 0.
        ;WITH UltimaHorneada AS (
            SELECT hor_numero_secuencia
            FROM (
                SELECT h.hor_numero_secuencia,
                       ROW_NUMBER() OVER (ORDER BY h.hor_hora_fin DESC) AS rn
                FROM plh.plh_hor_horneadas h
                WHERE h.hor_codigo_neg              = @CodigoNeg
                  AND h.hor_tienda_codigo           = @TiendaCodigo
                  AND h.hor_activa                  = 1
                  AND h.hor_solo_productos_directos = 0
                  AND h.hor_es_extraordinaria       = 0
            ) x
            WHERE x.rn = 1
        ),
        SumaHorneadas AS (
            SELECT ph.plh_pro_codigo, SUM(ph.plh_proyeccion) AS TotalRepartido
            FROM plh.plh_plh_plan_horneada ph
            WHERE ph.plh_codigo_neg    = @CodigoNeg
              AND ph.plh_tienda_codigo = @TiendaCodigo
              AND ph.plh_fecha         = @Fecha
            GROUP BY ph.plh_pro_codigo
        )
        UPDATE ph
        SET ph.plh_proyeccion = CAST(d.pld_proyectado_vender - s.TotalRepartido AS DECIMAL(18,4))
        FROM plh.plh_plh_plan_horneada ph
        INNER JOIN UltimaHorneada uh ON uh.hor_numero_secuencia = ph.plh_hor_numero_secuencia
        INNER JOIN plh.plh_pld_plan_detalle d ON  d.pld_codigo_neg    = ph.plh_codigo_neg
                                              AND d.pld_tienda_codigo  = ph.plh_tienda_codigo
                                              AND d.pld_fecha          = ph.plh_fecha
                                              AND d.pld_pro_codigo     = ph.plh_pro_codigo
        INNER JOIN SumaHorneadas s ON s.plh_pro_codigo = ph.plh_pro_codigo
        WHERE ph.plh_codigo_neg    = @CodigoNeg
          AND ph.plh_tienda_codigo = @TiendaCodigo
          AND ph.plh_fecha         = @Fecha;

        COMMIT TRANSACTION;

        SELECT @CodigoNeg AS pla_codigo_neg, @TiendaCodigo AS pla_tienda_codigo, @Fecha AS pla_fecha;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_pla_ActualizarDetalle]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @Fecha                  DATE,
    @ProCodigo              NVARCHAR(50),
    @InventarioInicial      DECIMAL(18,4),
    @ProyectadoVender       DECIMAL(18,4),
    @VentaHoy               DECIMAL(18,4),
    @TotalHornear           DECIMAL(18,4),
    @UsuarioCodigo          NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
    SET d.pld_inventario_inicial = @InventarioInicial,
        d.pld_proyectado_vender  = @ProyectadoVender,
        d.pld_venta_hoy          = @VentaHoy,
        d.pld_total_hornear      = @TotalHornear
    FROM plh.plh_pld_plan_detalle d
    INNER JOIN plh.plh_pla_planes p ON  p.pla_codigo_neg    = d.pld_codigo_neg
                                    AND p.pla_tienda_codigo  = d.pld_tienda_codigo
                                    AND p.pla_fecha          = d.pld_fecha
    WHERE d.pld_codigo_neg    = @CodigoNeg
      AND d.pld_tienda_codigo = @TiendaCodigo
      AND d.pld_fecha         = @Fecha
      AND d.pld_pro_codigo    = @ProCodigo
      AND p.pla_estado        <> 2;

    IF @@ROWCOUNT = 0
        RAISERROR('Detalle de plan no encontrado o plan cerrado.', 16, 1);
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_pla_ActualizarPlanHorneada]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @Fecha                  DATE,
    @ProCodigo              NVARCHAR(50),
    @HorNumeroSecuencia     INT,
    @Proyeccion             DECIMAL(18,4),
    @PedidoChef             DECIMAL(18,4),
    @CantidadHornear        DECIMAL(18,4),
    @UsuarioCodigo          NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE h
    SET h.plh_proyeccion                   = @Proyeccion,
        h.plh_pedido_chef                  = @PedidoChef,
        h.plh_cantidad_hornear             = @CantidadHornear,
        h.plh_fecha_actualizacion          = GETDATE(),
        h.plh_usuario_actualizacion_codigo = @UsuarioCodigo
    FROM plh.plh_plh_plan_horneada h
    INNER JOIN plh.plh_pla_planes p ON  p.pla_codigo_neg    = h.plh_codigo_neg
                                    AND p.pla_tienda_codigo  = h.plh_tienda_codigo
                                    AND p.pla_fecha          = h.plh_fecha
    WHERE h.plh_codigo_neg          = @CodigoNeg
      AND h.plh_tienda_codigo       = @TiendaCodigo
      AND h.plh_fecha               = @Fecha
      AND h.plh_pro_codigo          = @ProCodigo
      AND h.plh_hor_numero_secuencia = @HorNumeroSecuencia
      AND p.pla_estado              <> 2;

    IF @@ROWCOUNT = 0
        RAISERROR('Distribución de horneada no encontrada o plan cerrado.', 16, 1);
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_pla_ActualizarEstadoPlan]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @NuevoEstado    TINYINT,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NuevoEstado NOT IN (0, 1, 2)
    BEGIN
        RAISERROR('Estado de plan no válido. Use: 0=BORRADOR, 1=ACTIVO, 2=CERRADO.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_pla_planes
    SET pla_estado = @NuevoEstado
    WHERE pla_codigo_neg    = @CodigoNeg
      AND pla_tienda_codigo = @TiendaCodigo
      AND pla_fecha         = @Fecha;

    IF @@ROWCOUNT = 0
        RAISERROR('Plan no encontrado.', 16, 1);
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_pld_ActualizarTotalHornear]
    @CodigoNeg      NVARCHAR(10),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @ProCodigo      NVARCHAR(50),
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
    SET d.pld_total_hornear = (
        SELECT ISNULL(SUM(h.plh_cantidad_hornear), 0)
        FROM plh.plh_plh_plan_horneada h
        WHERE h.plh_codigo_neg    = @CodigoNeg
          AND h.plh_tienda_codigo = @TiendaCodigo
          AND h.plh_fecha         = @Fecha
          AND h.plh_pro_codigo    = @ProCodigo
    )
    FROM plh.plh_pld_plan_detalle d
    WHERE d.pld_codigo_neg    = @CodigoNeg
      AND d.pld_tienda_codigo = @TiendaCodigo
      AND d.pld_fecha         = @Fecha
      AND d.pld_pro_codigo    = @ProCodigo;
END;
GO
