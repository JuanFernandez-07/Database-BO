-- =============================================
-- Módulo: Catálogo de Productos
-- SPs: plh_cat_GuardarProducto
-- Base de datos: sm_backoffice_op
-- =============================================

USE [sm_backoffice_op];
GO

-- Estados cat_activo: 0=Inactivo, 1=Activo

CREATE OR ALTER PROCEDURE [plh].[plh_cat_GuardarProducto]
    @CodigoNeg               NVARCHAR(20),
    @TiendaCodigo            INT,
    @ProCodigo               NVARCHAR(50),
    @ProNombre               NVARCHAR(255),
    @Tipo                    NVARCHAR(50),
    @FactorConversion        DECIMAL(18,4),
    @Activo                  BIT,
    @AplicaControlReposteria BIT,
    @AplicaPedidoCocina      BIT,
    @EsEstacional            BIT,
    @RequiereFermentacion    BIT          = 1,
    -- CR-20260922-01 (HORNOS-F2-FRAC): lista de fracciones separadas por coma (ej. "0.25,0.5"),
    -- no un solo valor — un producto puede tener varias fracciones habilitadas a la vez.
    @FraccionBolsa           NVARCHAR(20) = '1.00',
    @SustitutoCodigo         NVARCHAR(50) = NULL,
    @UsuarioCodigo           NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Lookup automático del producto terminado via receta
    DECLARE @TerminadoCodigo NVARCHAR(50)  = NULL;
    DECLARE @TerminadoNombre NVARCHAR(255) = NULL;
    DECLARE @DataAreaId NVARCHAR(20);

    SELECT @DataAreaId = neg_referencia1
    FROM plh.Vw_plh_neg_Negocios
    WHERE CAST(neg_codigo AS NVARCHAR(20)) = @CodigoNeg;

    IF @DataAreaId IS NOT NULL
    BEGIN
        SELECT TOP 1
            @TerminadoCodigo = CAST(rd.Id_Receta AS NVARCHAR(50)),
            @TerminadoNombre = pt.NombreReceta
        FROM plh.Receta_detalle rd
        INNER JOIN plh.Phl_Vista_ProductosTerminados pt
            ON CAST(pt.Codigo_Receta AS NVARCHAR(50)) = CAST(rd.Id_Receta AS NVARCHAR(50))
           AND pt.DataAreaId = @DataAreaId
        WHERE rd.Codigo_Item  = @ProCodigo
          AND rd.Modificador <> 1
          AND rd.DataAreaId   = @DataAreaId
          AND CAST(rd.Id_Receta AS NVARCHAR(50)) NOT LIKE 'MOD%'
          AND (
              SELECT COUNT(*)
              FROM plh.Receta_detalle rd2
              WHERE rd2.Id_Receta   = rd.Id_Receta
                AND rd2.Modificador <> 1
                AND rd2.DataAreaId  = @DataAreaId
          ) = 1;
    END

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_cat_catalogo_productos
        WHERE cat_codigo_neg    = @CodigoNeg
          AND cat_tienda_codigo = @TiendaCodigo
          AND cat_pro_codigo    = @ProCodigo
    )
    BEGIN
        INSERT INTO plh.plh_cat_catalogo_productos (
            cat_codigo_neg, cat_tienda_codigo, cat_pro_codigo, cat_pro_nombre,
            cat_tipo, cat_factor_conversion, cat_activo,
            cat_aplica_control_reposteria, cat_aplica_pedido_cocina, cat_estacional,
            cat_pro_terminado_codigo, cat_pro_terminado_nombre,
            cat_requiere_fermentacion, cat_fraccion_bolsa,
            cat_pro_sustituto_codigo,
            cat_fecha_creacion, cat_usuario_creacion_codigo,
            cat_fecha_modificacion, cat_usuario_modificacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @ProCodigo, @ProNombre,
            @Tipo, @FactorConversion, @Activo,
            @AplicaControlReposteria, @AplicaPedidoCocina, @EsEstacional,
            @TerminadoCodigo, @TerminadoNombre,
            @RequiereFermentacion, @FraccionBolsa,
            @SustitutoCodigo,
            GETDATE(), @UsuarioCodigo,
            GETDATE(), @UsuarioCodigo
        );
    END
    ELSE
    BEGIN
        UPDATE plh.plh_cat_catalogo_productos
        SET cat_tipo                        = @Tipo,
            cat_factor_conversion           = @FactorConversion,
            cat_activo                      = @Activo,
            cat_aplica_control_reposteria   = @AplicaControlReposteria,
            cat_aplica_pedido_cocina        = @AplicaPedidoCocina,
            cat_estacional                  = @EsEstacional,
            cat_pro_terminado_codigo        = ISNULL(@TerminadoCodigo, cat_pro_terminado_codigo),
            cat_pro_terminado_nombre        = ISNULL(@TerminadoNombre, cat_pro_terminado_nombre),
            cat_requiere_fermentacion       = @RequiereFermentacion,
            cat_fraccion_bolsa              = @FraccionBolsa,
            cat_pro_sustituto_codigo        = @SustitutoCodigo,
            cat_fecha_modificacion          = GETDATE(),
            cat_usuario_modificacion_codigo = @UsuarioCodigo
        WHERE cat_codigo_neg    = @CodigoNeg
          AND cat_tienda_codigo = @TiendaCodigo
          AND cat_pro_codigo    = @ProCodigo;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Producto en catálogo no encontrado.', 16, 1);
            RETURN;
        END
    END

    SELECT @CodigoNeg AS cat_codigo_neg, @TiendaCodigo AS cat_tienda_codigo, @ProCodigo AS cat_pro_codigo;
END;
GO
