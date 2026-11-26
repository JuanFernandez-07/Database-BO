-- =============================================
-- Módulo: Devolución (DEVO)
-- SPs: plh_dev_GetDevoluciones, plh_dev_RegistrarDevolucion, plh_dev_EliminarDevolucion,
--      plh_dev_CerrarDia, plh_dev_AutorizarDevoluciones
-- Base de datos: sm_backoffice_op
-- Estados dev_estado: 0=PENDIENTE, 1=AUTORIZADO
-- =============================================

USE [sm_backoffice_op];
GO

-- ─── SP: Obtener Devoluciones del Día ────────────────────────────────────────
-- Llamado via Dapper en DevolucionRepository.cs (excepción a la regla EF Core
-- porque requiere JOIN cross-DB a SM_BO_DW para obtener nombre y unidad del producto).

CREATE OR ALTER PROCEDURE [plh].[plh_dev_GetDevoluciones]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.dev_id,
        d.dev_codigo_neg,
        d.dev_tienda_codigo,
        d.dev_fecha_registro,
        d.dev_fecha_venta,
        d.dev_pro_codigo,
        d.dev_cantidad,
        d.dev_observaciones,
        d.dev_dia_cerrado,
        d.dev_fecha_creacion,
        d.dev_usuario_creacion_codigo,
        p.Nombre            AS pro_nombre,
        p.UnidadEstandar    AS pro_unidad_estandar
    FROM plh.plh_dev_devoluciones d
    INNER JOIN [SM_BO_DW].[PDS].[PDS_Inventario_Catalogo] p
           ON p.Codigo      = d.dev_pro_codigo
          AND p.DataAreaid  = d.dev_codigo_neg
    WHERE d.dev_codigo_neg     = @CodigoNeg
      AND d.dev_tienda_codigo  = @TiendaCodigo
      AND d.dev_fecha_registro = @Fecha
    ORDER BY p.Nombre, d.dev_fecha_creacion;
END;
GO

-- ─── Migración: columna horneada en devoluciones ─────────────────────────────

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_dev_devoluciones')
      AND name = 'dev_hor_numero_secuencia'
)
BEGIN
    ALTER TABLE plh.plh_dev_devoluciones
        ADD dev_hor_numero_secuencia INT NULL;
END
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_dev_RegistrarDevolucion]
    @CodigoNeg            NVARCHAR(20),
    @TiendaCodigo         INT,
    @FechaRegistro        DATE,
    @FechaVenta           DATE,
    @ProCodigo            NVARCHAR(50),
    @Cantidad             DECIMAL(18,4),
    @Observaciones        NVARCHAR(500) = NULL,
    @UsuarioCodigo        NVARCHAR(50),
    @Reemplazar           BIT = 0,
    @HorNumeroSecuencia   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaVenta > @FechaRegistro
    BEGIN
        RAISERROR('La fecha de venta no puede ser posterior a la fecha de registro.', 16, 1);
        RETURN;
    END

    -- Reemplazar con 0 = borrar registros previos e insertar uno con cantidad 0 (devo confirmada en cero)
    IF @Reemplazar = 1 AND @Cantidad = 0
    BEGIN
        DELETE FROM plh.plh_dev_devoluciones
        WHERE dev_codigo_neg          = @CodigoNeg
          AND dev_tienda_codigo       = @TiendaCodigo
          AND dev_fecha_registro      = @FechaRegistro
          AND dev_pro_codigo          = @ProCodigo
          AND dev_dia_cerrado         = 0
          AND ((@HorNumeroSecuencia IS NULL AND dev_hor_numero_secuencia IS NULL)
               OR dev_hor_numero_secuencia = @HorNumeroSecuencia);

        INSERT INTO plh.plh_dev_devoluciones (
            dev_codigo_neg, dev_tienda_codigo,
            dev_fecha_registro, dev_fecha_venta,
            dev_pro_codigo, dev_cantidad, dev_observaciones,
            dev_dia_cerrado, dev_hor_numero_secuencia,
            dev_fecha_creacion, dev_usuario_creacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo,
            @FechaRegistro, @FechaVenta,
            @ProCodigo, 0, @Observaciones,
            0, @HorNumeroSecuencia,
            GETDATE(), @UsuarioCodigo
        );

        SELECT SCOPE_IDENTITY() AS dev_id;
        RETURN;
    END

    IF @Cantidad <= 0
    BEGIN
        RAISERROR('La cantidad debe ser mayor a cero.', 16, 1);
        RETURN;
    END

    -- El cierre de día solo aplica a productos generales; los de repostería siempre pueden registrarse
    DECLARE @EsReposteria BIT = 0;
    SELECT TOP 1 @EsReposteria = CAST(ISNULL(cat_aplica_control_reposteria, 0) AS BIT)
    FROM plh.plh_cat_catalogo_productos
    WHERE cat_pro_codigo    = @ProCodigo
      AND cat_codigo_neg    = @CodigoNeg
      AND cat_tienda_codigo IN (0, @TiendaCodigo)
    ORDER BY cat_tienda_codigo DESC;

    IF @EsReposteria = 0 AND EXISTS (
        SELECT 1 FROM plh.plh_dev_devoluciones
        WHERE dev_codigo_neg     = @CodigoNeg
          AND dev_tienda_codigo  = @TiendaCodigo
          AND dev_fecha_registro = @FechaRegistro
          AND dev_dia_cerrado    = 1
    )
    BEGIN
        RAISERROR('El día ya fue cerrado. No se pueden registrar nuevas devoluciones.', 16, 1);
        RETURN;
    END

    -- Modo reemplazo: elimina registros previos no cerrados del mismo producto/horneada para esa fecha
    IF @Reemplazar = 1
    BEGIN
        DELETE FROM plh.plh_dev_devoluciones
        WHERE dev_codigo_neg          = @CodigoNeg
          AND dev_tienda_codigo       = @TiendaCodigo
          AND dev_fecha_registro      = @FechaRegistro
          AND dev_pro_codigo          = @ProCodigo
          AND dev_dia_cerrado         = 0
          AND ((@HorNumeroSecuencia IS NULL AND dev_hor_numero_secuencia IS NULL)
               OR dev_hor_numero_secuencia = @HorNumeroSecuencia);
    END

    INSERT INTO plh.plh_dev_devoluciones (
        dev_codigo_neg, dev_tienda_codigo,
        dev_fecha_registro, dev_fecha_venta,
        dev_pro_codigo, dev_cantidad, dev_observaciones,
        dev_dia_cerrado, dev_hor_numero_secuencia,
        dev_fecha_creacion, dev_usuario_creacion_codigo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo,
        @FechaRegistro, @FechaVenta,
        @ProCodigo, @Cantidad, @Observaciones,
        0, @HorNumeroSecuencia,
        GETDATE(), @UsuarioCodigo
    );

    SELECT SCOPE_IDENTITY() AS dev_id;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_dev_EliminarDevolucion]
    @DevolucionId   BIGINT,
    @CodigoNeg      NVARCHAR(20),
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_dev_devoluciones
        WHERE dev_id          = @DevolucionId
          AND dev_codigo_neg  = @CodigoNeg
          AND dev_dia_cerrado = 0
    )
    BEGIN
        RAISERROR('Devolución no encontrada o el día ya fue cerrado.', 16, 1);
        RETURN;
    END

    DELETE FROM plh.plh_dev_devoluciones
    WHERE dev_id         = @DevolucionId
      AND dev_codigo_neg = @CodigoNeg;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_dev_CerrarDia]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Solo gestiona devoluciones de productos generales (no repostería).
    -- Las de repostería se cierran al hacer "Cerrar DEVO" en Control Repostería.
    IF NOT EXISTS (
        SELECT 1
        FROM plh.plh_dev_devoluciones d
        OUTER APPLY (
            SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
            FROM plh.plh_cat_catalogo_productos c
            WHERE c.cat_pro_codigo    = d.dev_pro_codigo
              AND c.cat_codigo_neg    = d.dev_codigo_neg
              AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
            ORDER BY c.cat_tienda_codigo DESC
        ) tipo
        WHERE d.dev_codigo_neg     = @CodigoNeg
          AND d.dev_tienda_codigo  = @TiendaCodigo
          AND d.dev_fecha_registro = @Fecha
          AND ISNULL(tipo.EsReposteria, 0) = 0
    )
    BEGIN
        RAISERROR('No hay devoluciones generales registradas para esta fecha.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM plh.plh_dev_devoluciones d
        OUTER APPLY (
            SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
            FROM plh.plh_cat_catalogo_productos c
            WHERE c.cat_pro_codigo    = d.dev_pro_codigo
              AND c.cat_codigo_neg    = d.dev_codigo_neg
              AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
            ORDER BY c.cat_tienda_codigo DESC
        ) tipo
        WHERE d.dev_codigo_neg     = @CodigoNeg
          AND d.dev_tienda_codigo  = @TiendaCodigo
          AND d.dev_fecha_registro = @Fecha
          AND d.dev_dia_cerrado    = 0
          AND ISNULL(tipo.EsReposteria, 0) = 0
    )
    BEGIN
        RAISERROR('El día ya fue cerrado anteriormente.', 16, 1);
        RETURN;
    END

    UPDATE d
    SET d.dev_dia_cerrado = 1
    FROM plh.plh_dev_devoluciones d
    OUTER APPLY (
        SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
        FROM plh.plh_cat_catalogo_productos c
        WHERE c.cat_pro_codigo    = d.dev_pro_codigo
          AND c.cat_codigo_neg    = d.dev_codigo_neg
          AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
        ORDER BY c.cat_tienda_codigo DESC
    ) tipo
    WHERE d.dev_codigo_neg     = @CodigoNeg
      AND d.dev_tienda_codigo  = @TiendaCodigo
      AND d.dev_fecha_registro = @Fecha
      AND ISNULL(tipo.EsReposteria, 0) = 0;

    SELECT @@ROWCOUNT AS filas_cerradas;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_dev_CerrarDiaReposteria]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Cierra devoluciones de productos de repostería para esta fecha.
    -- No genera error si no hay registros (puede llamarse siempre desde Control Repostería).
    UPDATE d
    SET d.dev_dia_cerrado = 1
    FROM plh.plh_dev_devoluciones d
    OUTER APPLY (
        SELECT TOP 1 CAST(ISNULL(c.cat_aplica_control_reposteria, 0) AS BIT) AS EsReposteria
        FROM plh.plh_cat_catalogo_productos c
        WHERE c.cat_pro_codigo    = d.dev_pro_codigo
          AND c.cat_codigo_neg    = d.dev_codigo_neg
          AND c.cat_tienda_codigo IN (0, d.dev_tienda_codigo)
        ORDER BY c.cat_tienda_codigo DESC
    ) tipo
    WHERE d.dev_codigo_neg     = @CodigoNeg
      AND d.dev_tienda_codigo  = @TiendaCodigo
      AND d.dev_fecha_registro = @Fecha
      AND d.dev_dia_cerrado    = 0
      AND ISNULL(tipo.EsReposteria, 0) = 1;

    SELECT @@ROWCOUNT AS filas_cerradas;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_dev_AutorizarDevoluciones]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @FechaRegistro          DATE,
    @UsuarioAutorizacion    NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_dev_devoluciones
    SET dev_estado               = 1,
        dev_usuario_autorizacion = @UsuarioAutorizacion,
        dev_fecha_autorizacion   = GETDATE()
    WHERE dev_codigo_neg     = @CodigoNeg
      AND dev_tienda_codigo  = @TiendaCodigo
      AND dev_fecha_registro = @FechaRegistro
      AND dev_estado         = 0;

    IF @@ROWCOUNT = 0
        RAISERROR('No hay devoluciones pendientes para autorizar en esa fecha.', 16, 1);
END;
GO
