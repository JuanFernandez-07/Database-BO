-- =============================================
-- CR-20260816-01 Devolución Cocina — DEPLOY A PRODUCCIÓN, parte 2 de 3: SPs
--
-- Los 2 stored procedures nuevos de Recepción Chef. Requiere haber corrido
-- antes 030_Produccion_Schema.sql (crea la tabla plh_rec_recepciones_chef).
-- CREATE OR ALTER — idempotente, seguro de re-correr.
--
-- Después de este archivo, el paso final es desplegar el módulo de
-- Devolución completo (ver 07_Devolucion.sql en esta misma carpeta — ya
-- contiene el fix de rec_cantidad_aceptada validado, reemplaza completo a
-- Database/sm_backoffice_op/StoredProceduresFinal/07_Devolucion.sql).
-- =============================================

USE [sm_backoffice_op];
GO

-- ═══════════════════════════════════════════════════════════════════════════
-- Registrar resultado de recepción del chef (UPSERT por horneada)
-- Espejo de plh_prh_RegistrarResultado, sin el chequeo de encabezado/horno
-- (el chef no tiene proceso de fermentación/horno propio) y sin
-- "CantidadFinal" (campo redundante específico de Recepción de Horneado).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE [plh].[plh_rec_RegistrarResultadoChef]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @CantidadAceptada   DECIMAL(18,4),
    @CantidadAddFal     DECIMAL(18,4),
    @MotivoRechazo      NVARCHAR(200) = NULL,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @PedidoChef DECIMAL(18,4) = 0;
        SELECT @PedidoChef = ped_cantidad
        FROM plh.plh_ped_pedidos_cocina
        WHERE ped_codigo_neg          = @CodigoNeg
          AND ped_tienda_codigo       = @TiendaCodigo
          AND ped_fecha               = @Fecha
          AND ped_pro_codigo          = @ProCodigo
          AND ped_hor_numero_secuencia = @HorNumeroSecuencia;

        IF @PedidoChef IS NULL OR @PedidoChef <= 0
        BEGIN
            RAISERROR('No hay pedido de cocina para este producto en esta horneada.', 16, 1);
            RETURN;
        END

        -- La vendedora recepciona primero sobre el total horneado (Recepción de
        -- Horneado); cocina no puede recepcionar hasta que ese registro exista.
        DECLARE @HorneadoAceptado DECIMAL(18,4) = NULL;
        SELECT @HorneadoAceptado = prh_cantidad_aceptada
        FROM plh.plh_prh_proceso_horneado_detalle
        WHERE prh_codigo_neg           = @CodigoNeg
          AND prh_tienda_codigo        = @TiendaCodigo
          AND prh_fecha                = @Fecha
          AND prh_pro_codigo           = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

        IF @HorneadoAceptado IS NULL
        BEGIN
            RAISERROR('La vendedora todavía no ha recepcionado este producto en Recepción de Horneado.', 16, 1);
            RETURN;
        END

        -- CR-20260911-01: ADD/FAL positivo = recibió más de lo pedido (suma),
        -- negativo = recibió menos (resta). El motivo solo es obligatorio en
        -- el caso de faltante.
        IF @CantidadAddFal < 0 AND @MotivoRechazo IS NULL
        BEGIN
            RAISERROR('El motivo es obligatorio cuando hay unidades faltantes.', 16, 1);
            RETURN;
        END

        -- Aceptado = Pedido Chef + ADD/FAL. Sin tope contra lo horneado — el
        -- único límite es que no puede resultar negativo.
        IF @CantidadAceptada <> (@PedidoChef + @CantidadAddFal)
        BEGIN
            RAISERROR('La cantidad aceptada debe ser igual al pedido de cocina más el ADD/FAL.', 16, 1);
            RETURN;
        END

        IF @CantidadAceptada < 0
        BEGIN
            RAISERROR('La cantidad aceptada no puede ser negativa.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM plh.plh_rec_recepciones_chef
            WHERE rec_codigo_neg          = @CodigoNeg
              AND rec_tienda_codigo       = @TiendaCodigo
              AND rec_fecha               = @Fecha
              AND rec_pro_codigo          = @ProCodigo
              AND rec_hor_numero_secuencia = @HorNumeroSecuencia
        )
        BEGIN
            UPDATE plh.plh_rec_recepciones_chef
            SET rec_cantidad_aceptada       = @CantidadAceptada,
                rec_cantidad_add_fal        = @CantidadAddFal,
                rec_motivo_rechazo          = @MotivoRechazo,
                rec_revisado                = 1,
                rec_fecha_revision          = GETDATE(),
                rec_usuario_revision_codigo = @UsuarioCodigo,
                rec_usuario_registro_codigo = @UsuarioCodigo
            WHERE rec_codigo_neg          = @CodigoNeg
              AND rec_tienda_codigo       = @TiendaCodigo
              AND rec_fecha               = @Fecha
              AND rec_pro_codigo          = @ProCodigo
              AND rec_hor_numero_secuencia = @HorNumeroSecuencia;
        END
        ELSE
        BEGIN
            INSERT INTO plh.plh_rec_recepciones_chef (
                rec_codigo_neg, rec_tienda_codigo, rec_fecha, rec_pro_codigo, rec_hor_numero_secuencia,
                rec_cantidad_aceptada, rec_cantidad_add_fal, rec_motivo_rechazo,
                rec_revisado, rec_fecha_revision, rec_usuario_revision_codigo,
                rec_fecha_registro, rec_usuario_registro_codigo
            )
            VALUES (
                @CodigoNeg, @TiendaCodigo, @Fecha, @ProCodigo, @HorNumeroSecuencia,
                @CantidadAceptada, @CantidadAddFal, @MotivoRechazo,
                1, GETDATE(), @UsuarioCodigo,
                GETDATE(), @UsuarioCodigo
            );
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ═══════════════════════════════════════════════════════════════════════════
-- Marcar/desmarcar revisado (destildar para poder volver a editar)
-- Espejo de plh_prh_MarcarRevisado.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR ALTER PROCEDURE [plh].[plh_rec_MarcarRevisadoChef]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @Revisado           BIT,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_rec_recepciones_chef
    SET rec_revisado                = @Revisado,
        rec_fecha_revision          = CASE WHEN @Revisado = 1 THEN GETDATE() ELSE NULL END,
        rec_usuario_revision_codigo = CASE WHEN @Revisado = 1 THEN @UsuarioCodigo ELSE NULL END
    WHERE rec_codigo_neg          = @CodigoNeg
      AND rec_tienda_codigo       = @TiendaCodigo
      AND rec_fecha               = @Fecha
      AND rec_pro_codigo          = @ProCodigo
      AND rec_hor_numero_secuencia = @HorNumeroSecuencia;

    IF @@ROWCOUNT = 0
        RAISERROR('No hay recepción registrada para este producto en esta horneada.', 16, 1);
END;
GO
