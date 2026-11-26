-- =============================================
-- Módulo: Pedido de Cocina
-- SPs: plh_ped_GuardarPedidoCocina, plh_ped_ActualizarEstadoPedido
-- Base de datos: sm_backoffice_op
-- Estados ped_estado: 0=PENDIENTE, 1=ENVIADO, 2=COMPLETADO, 3=CANCELADO
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_ped_GuardarPedidoCocina]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @Cantidad           DECIMAL(18,4),
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM plh.plh_ped_pedidos_cocina
        WHERE ped_codigo_neg          = @CodigoNeg
          AND ped_tienda_codigo       = @TiendaCodigo
          AND ped_fecha               = @Fecha
          AND ped_pro_codigo          = @ProCodigo
          AND ped_hor_numero_secuencia = @HorNumeroSecuencia
    )
    BEGIN
        UPDATE plh.plh_ped_pedidos_cocina
        SET ped_cantidad = @Cantidad
        WHERE ped_codigo_neg          = @CodigoNeg
          AND ped_tienda_codigo       = @TiendaCodigo
          AND ped_fecha               = @Fecha
          AND ped_pro_codigo          = @ProCodigo
          AND ped_hor_numero_secuencia = @HorNumeroSecuencia;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM plh.plh_hor_horneadas
            WHERE hor_codigo_neg          = @CodigoNeg
              AND hor_tienda_codigo       = @TiendaCodigo
              AND hor_numero_secuencia    = @HorNumeroSecuencia
              AND hor_aplica_pedido_cocina = 1
              AND hor_activa              = 1
        )
        BEGIN
            RAISERROR('La horneada no acepta pedidos de cocina o no está activa.', 16, 1);
            RETURN;
        END

        INSERT INTO plh.plh_ped_pedidos_cocina (
            ped_codigo_neg, ped_tienda_codigo, ped_fecha,
            ped_pro_codigo, ped_hor_numero_secuencia, ped_cantidad,
            ped_estado, ped_fecha_creacion, ped_usuario_creacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @Fecha,
            @ProCodigo, @HorNumeroSecuencia, @Cantidad,
            0, GETDATE(), @UsuarioCodigo
        );
    END

    SELECT @CodigoNeg AS ped_codigo_neg, @TiendaCodigo AS ped_tienda_codigo,
           @Fecha AS ped_fecha, @ProCodigo AS ped_pro_codigo,
           @HorNumeroSecuencia AS ped_hor_numero_secuencia;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_ped_ActualizarEstadoPedido]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @NuevoEstado        TINYINT,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NuevoEstado NOT IN (0, 1, 2, 3)
    BEGIN
        RAISERROR('Estado no válido. Use: 0=PENDIENTE, 1=ENVIADO, 2=COMPLETADO, 3=CANCELADO.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_ped_pedidos_cocina
    SET ped_estado = @NuevoEstado
    WHERE ped_codigo_neg          = @CodigoNeg
      AND ped_tienda_codigo       = @TiendaCodigo
      AND ped_fecha               = @Fecha
      AND ped_pro_codigo          = @ProCodigo
      AND ped_hor_numero_secuencia = @HorNumeroSecuencia;

    IF @@ROWCOUNT = 0
        RAISERROR('Pedido no encontrado.', 16, 1);
END;
GO
