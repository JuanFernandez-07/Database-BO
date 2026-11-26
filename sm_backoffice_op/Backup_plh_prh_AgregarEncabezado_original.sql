-- =============================================
-- plh_prh_AgregarEncabezado — versión fila por fila (la versión batch/JSON quedó
-- descartada, esta es la que está en uso).
--
-- @EsExtraordinario (Pedido Extra, rango 900-999 por tienda/fecha): cuando viene en 1,
-- el SP IGNORA @HorNumeroSecuencia y asigna el siguiente número libre del rango —
-- serializado con sp_getapplock para que dos envíos simultáneos no obtengan el mismo
-- número. Así cada envío de Pedido Extra del mismo producto/día cae en una fila nueva
-- e independiente en vez de pisar/reabrir una anterior.
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_prh_AgregarEncabezado]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @Fecha                  DATE,
    @ProCodigo              NVARCHAR(50),
    @HorNumeroSecuencia     INT,
    @CantidadBolsas         DECIMAL(18,4),
    @RackAsignado           NVARCHAR(50)  = NULL,
    @Observaciones          NVARCHAR(500) = NULL,
    @UsuarioCodigo          NVARCHAR(50),
    @NumeroCheck            NVARCHAR(50)  = NULL,
    @EsExtraordinario       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_codigo_neg    = @CodigoNeg
          AND prc_tienda_codigo = @TiendaCodigo
          AND prc_fecha         = @Fecha
          AND prc_estado        = 1
    )
    BEGIN
        RAISERROR('El proceso no existe o no está EN_PROCESO.', 16, 1);
        RETURN;
    END

    IF @EsExtraordinario = 1
    BEGIN
        DECLARE @LockResource NVARCHAR(200) =
            CONCAT('PedidoExtra_', @CodigoNeg, '_', @TiendaCodigo, '_', CONVERT(NVARCHAR(10), @Fecha, 23));
        DECLARE @LockResult INT;

        BEGIN TRANSACTION;

        EXEC @LockResult = sp_getapplock
            @Resource = @LockResource, @LockMode = 'Exclusive',
            @LockOwner = 'Transaction', @LockTimeout = 5000;

        IF @LockResult < 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('No se pudo registrar el Pedido Extra, intenta de nuevo en unos segundos.', 16, 1);
            RETURN;
        END

        SELECT @HorNumeroSecuencia = ISNULL(MAX(prh_hor_numero_secuencia), 899) + 1
        FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_hor_numero_secuencia BETWEEN 900 AND 999;

        IF @HorNumeroSecuencia > 999
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Se alcanzó el máximo de Pedidos Extra para esta tienda y fecha.', 16, 1);
            RETURN;
        END
    END
    ELSE IF EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
    )
    BEGIN
        RAISERROR('El producto ya fue agregado a esta horneada en el proceso actual.', 16, 1);
        RETURN;
    END

    DECLARE @EstadoFermentacionInicial INT;
    SELECT @EstadoFermentacionInicial = CASE WHEN cat_requiere_fermentacion = 1 THEN 0 ELSE 2 END
    FROM plh.plh_cat_catalogo_productos
    WHERE cat_pro_codigo    = @ProCodigo
      AND cat_codigo_neg    = @CodigoNeg
      AND cat_tienda_codigo IN (0, @TiendaCodigo)
      AND cat_activo        = 1;

    -- Si el producto no está en el catálogo activo, asumir que requiere fermentación (estado 0 = Pendiente)
    SET @EstadoFermentacionInicial = ISNULL(@EstadoFermentacionInicial, 0);

    DECLARE @OmitioFermentacion BIT = CASE WHEN @EstadoFermentacionInicial = 2 THEN 1 ELSE 0 END;

    INSERT INTO plh.plh_prh_proceso_horneado_encabezado (
        prh_codigo_neg, prh_tienda_codigo, prh_fecha,
        prh_pro_codigo, prh_hor_numero_secuencia, prh_cantidad_bolsas,
        prh_estado_fermentacion, prh_omitio_fermentacion,
        prh_rack_asignado, prh_observaciones, prh_numero_check,
        prh_fecha_actualizacion, prh_usuario_actualizacion_codigo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        @ProCodigo, @HorNumeroSecuencia, @CantidadBolsas,
        @EstadoFermentacionInicial, @OmitioFermentacion,
        @RackAsignado, @Observaciones, @NumeroCheck,
        GETDATE(), @UsuarioCodigo
    );

    IF @EsExtraordinario = 1
        COMMIT TRANSACTION;

    SELECT @CodigoNeg AS prh_codigo_neg, @TiendaCodigo AS prh_tienda_codigo,
           @Fecha AS prh_fecha, @ProCodigo AS prh_pro_codigo,
           @HorNumeroSecuencia AS prh_hor_numero_secuencia;
END;
GO
