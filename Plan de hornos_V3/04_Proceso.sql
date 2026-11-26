-- =============================================
-- Módulo: Proceso de Horneado
-- SPs: plh_prc_IniciarProceso, plh_prc_FinalizarProceso,
--      plh_prh_AgregarEncabezado,
--      plh_prh_IniciarFermentacion, plh_prh_FinalizarFermentacion,
--      plh_prh_OmitirFermentacion,
--      plh_prh_IniciarHorneado, plh_prh_FinalizarHorneado,
--      plh_prh_ActualizarCantidadBolsas,
--      plh_prh_RegistrarResultado, plh_prh_MarcarRevisado
-- Base de datos: sm_backoffice_op
-- Estados prc_estado:         0=PENDIENTE, 1=EN_PROCESO, 2=FINALIZADO
-- Estados prh_estado_ferment: 0=PENDIENTE, 1=EN_FERMENTACION, 2=FERMENTADO, 3=COMPLETADO
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_prc_IniciarProceso]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_codigo_neg    = @CodigoNeg
          AND prc_tienda_codigo = @TiendaCodigo
          AND prc_fecha         = @Fecha
    )
    BEGIN
        RAISERROR('Ya existe un proceso iniciado para esta fecha y tienda.', 16, 1);
        RETURN;
    END

    INSERT INTO plh.plh_prc_procesos (
        prc_codigo_neg, prc_tienda_codigo, prc_fecha,
        prc_estado, prc_fecha_inicio,
        prc_usuario_inicio_codigo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        1, GETDATE(),
        @UsuarioCodigo
    );

    SELECT @CodigoNeg AS prc_codigo_neg, @TiendaCodigo AS prc_tienda_codigo, @Fecha AS prc_fecha;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prc_FinalizarProceso]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_prc_procesos
    SET prc_estado              = 2,
        prc_fecha_fin           = GETDATE(),
        prc_usuario_fin_codigo  = @UsuarioCodigo
    WHERE prc_codigo_neg    = @CodigoNeg
      AND prc_tienda_codigo = @TiendaCodigo
      AND prc_fecha         = @Fecha
      AND prc_estado        = 1;

    IF @@ROWCOUNT = 0
        RAISERROR('Proceso no encontrado o no está EN_PROCESO.', 16, 1);
END;
GO

-- =============================================
-- CR-20260914-01: reabre un proceso ya FINALIZADO para poder registrar un Pedido
-- Extraordinario — por diseño, el Pedido Extraordinario se habilita justo cuando todas
-- las horneadas regulares ya bloquearon, momento en el que el proceso del día suele
-- estar (o quedar, por auto-cierre) FINALIZADO. Sin esto, plh_prh_AgregarEncabezado
-- rechaza el registro con "El proceso no existe o no está EN_PROCESO."
-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prc_ReabrirProceso]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_prc_procesos
    SET prc_estado              = 1,
        prc_fecha_fin           = NULL,
        prc_usuario_fin_codigo  = NULL
    WHERE prc_codigo_neg    = @CodigoNeg
      AND prc_tienda_codigo = @TiendaCodigo
      AND prc_fecha         = @Fecha
      AND prc_estado        = 2;

    IF @@ROWCOUNT = 0
        RAISERROR('Proceso no encontrado o no está FINALIZADO.', 16, 1);
END;
GO

-- =============================================

-- Fila por fila (la versión batch/JSON quedó descartada — ver
-- Backup_plh_prh_AgregarEncabezado_original.sql, esta es la misma base).
--
-- @EsExtraordinario (Pedido Extra, rango 900-999 por tienda/fecha): cuando viene en 1,
-- el SP IGNORA @HorNumeroSecuencia y asigna el siguiente número libre del rango —
-- serializado con sp_getapplock para que dos envíos simultáneos no obtengan el mismo
-- número. Así cada envío de Pedido Extra del mismo producto/día cae en una fila nueva
-- e independiente en vez de pisar/reabrir una anterior.
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

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_IniciarFermentacion]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @RackAsignado       NVARCHAR(50)  = NULL,
    @TemperaturaHorno   DECIMAL(5, 1) = NULL,
    @Observaciones      NVARCHAR(500) = NULL,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
          AND prh_estado_fermentacion = 0
    )
    BEGIN
        RAISERROR('El encabezado no existe o no está en estado PENDIENTE para iniciar fermentación.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_estado_fermentacion          = 1,
        prh_fecha_inicio_ferment         = GETDATE(),
        prh_rack_asignado                = ISNULL(@RackAsignado, prh_rack_asignado),
        prh_temperatura_horno            = ISNULL(@TemperaturaHorno, prh_temperatura_horno),
        prh_observaciones                = ISNULL(@Observaciones, prh_observaciones),
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

    -- tip_id 1 = INICIO_FERMENTACION
    INSERT INTO plh.plh_trz_trazabilidad (
        trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha,
        trz_prh_pro_codigo, trz_prh_hor_numero_secuencia,
        trz_tip_id, trz_fecha_evento, trz_usuario_codigo, trz_observaciones
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        @ProCodigo, @HorNumeroSecuencia,
        1, GETDATE(), @UsuarioCodigo,
        CASE WHEN @TemperaturaHorno IS NOT NULL
             THEN ISNULL(@Observaciones + ' | ', '') + 'Temp: ' + CAST(@TemperaturaHorno AS NVARCHAR) + '°C'
             ELSE @Observaciones
        END
    );
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_FinalizarFermentacion]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @Observaciones      NVARCHAR(500) = NULL,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
          AND prh_estado_fermentacion = 1
    )
    BEGIN
        RAISERROR('El encabezado no existe o no está EN_FERMENTACION.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_estado_fermentacion          = 2,
        prh_fecha_fin_ferment            = GETDATE(),
        prh_observaciones                = ISNULL(@Observaciones, prh_observaciones),
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

    -- tip_id 2 = FIN_FERMENTACION
    INSERT INTO plh.plh_trz_trazabilidad (
        trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha,
        trz_prh_pro_codigo, trz_prh_hor_numero_secuencia,
        trz_tip_id, trz_fecha_evento, trz_usuario_codigo, trz_observaciones
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        @ProCodigo, @HorNumeroSecuencia,
        2, GETDATE(), @UsuarioCodigo, @Observaciones
    );
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_OmitirFermentacion]
    @CodigoNeg                   NVARCHAR(10),
    @TiendaCodigo                INT,
    @Fecha                       DATE,
    @ProCodigo                   NVARCHAR(50),
    @HorNumeroSecuencia          INT,
    @TemperaturaDescongelamiento DECIMAL(5,1) = NULL,
    @UsuarioCodigo               NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
    )
    BEGIN
        RAISERROR('Encabezado no encontrado.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
          AND prh_estado_fermentacion <> 0
    )
    BEGIN
        RAISERROR('Solo se puede omitir fermentación en estado PENDIENTE.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_omitio_fermentacion          = 1,
        prh_estado_fermentacion          = 2,
        prh_temperatura_descongelamiento = @TemperaturaDescongelamiento,
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_IniciarHorneado]
    @CodigoNeg           NVARCHAR(10),
    @TiendaCodigo        INT,
    @Fecha               DATE,
    @ProCodigo           NVARCHAR(50),
    @HorNumeroSecuencia  INT,
    @TemperaturaPreheat  DECIMAL(5,1) = NULL,
    @TemperaturaEntrada  DECIMAL(5,1) = NULL,
    @TemperaturaPreheat2 DECIMAL(5,1) = NULL,
    @TemperaturaHorno2   DECIMAL(5,1) = NULL,
    @VaporSegundos       INT          = NULL,
    @UsuarioCodigo       NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
    )
    BEGIN
        RAISERROR('Encabezado no encontrado.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_temperatura_preheat          = @TemperaturaPreheat,
        prh_temperatura_horno            = @TemperaturaEntrada,
        prh_temperatura_preheat_2        = @TemperaturaPreheat2,
        prh_temperatura_horno_2          = @TemperaturaHorno2,
        prh_vapor_segundos               = @VaporSegundos,
        prh_fecha_inicio_horneado        = GETDATE(),
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

    -- tip_id 3 = INICIO_HORNEADO
    INSERT INTO plh.plh_trz_trazabilidad (
        trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha,
        trz_prh_pro_codigo, trz_prh_hor_numero_secuencia,
        trz_tip_id, trz_fecha_evento, trz_usuario_codigo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        @ProCodigo, @HorNumeroSecuencia,
        3, GETDATE(), @UsuarioCodigo
    );
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_FinalizarHorneado]
    @CodigoNeg          NVARCHAR(10),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @Observaciones      NVARCHAR(500) = NULL,
    @UsuarioCodigo      NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia
    )
    BEGIN
        RAISERROR('Encabezado no encontrado.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_fecha_fin_horneado           = GETDATE(),
        prh_observaciones                = ISNULL(@Observaciones, prh_observaciones),
        prh_estado_fermentacion          = 3,
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

    -- tip_id 4 = FIN_HORNEADO
    INSERT INTO plh.plh_trz_trazabilidad (
        trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha,
        trz_prh_pro_codigo, trz_prh_hor_numero_secuencia,
        trz_tip_id, trz_fecha_evento, trz_usuario_codigo, trz_observaciones
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @Fecha,
        @ProCodigo, @HorNumeroSecuencia,
        4, GETDATE(), @UsuarioCodigo, @Observaciones
    );
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_ActualizarCantidadBolsas]
    @CodigoNeg          NVARCHAR(10),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @CantidadBolsas     DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_cantidad_bolsas = @CantidadBolsas
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;
END;
GO

-- ─── Migración: ampliar motivo_rechazo para texto libre ──────────────────────

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('plh.plh_prh_proceso_horneado_detalle')
      AND name = 'prh_motivo_rechazo'
      AND max_length = 100  -- NVARCHAR(50) → 100 bytes
)
BEGIN
    ALTER TABLE plh.plh_prh_proceso_horneado_detalle
        ALTER COLUMN prh_motivo_rechazo NVARCHAR(200) NULL;
END
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_RegistrarResultado]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT,
    @CantidadAceptada   DECIMAL(18,4),
    @CantidadRechazada  DECIMAL(18,4),
    @MotivoRechazo      NVARCHAR(200) = NULL,
    @CantidadFinal      DECIMAL(18,4),
    @Observaciones      NVARCHAR(500) = NULL,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1 FROM plh.plh_prh_proceso_horneado_encabezado
            WHERE prh_codigo_neg          = @CodigoNeg
              AND prh_tienda_codigo       = @TiendaCodigo
              AND prh_fecha               = @Fecha
              AND prh_pro_codigo          = @ProCodigo
              AND prh_hor_numero_secuencia = @HorNumeroSecuencia
              AND prh_fecha_fin_horneado  IS NOT NULL
        )
        BEGIN
            RAISERROR('Encabezado no encontrado o el producto aún no ha salido del horno.', 16, 1);
            RETURN;
        END

        IF @CantidadRechazada > 0 AND @MotivoRechazo IS NULL
        BEGIN
            RAISERROR('El motivo de rechazo es obligatorio cuando la cantidad rechazada es mayor a 0.', 16, 1);
            RETURN;
        END

        IF @CantidadFinal <> @CantidadAceptada
        BEGIN
            RAISERROR('La cantidad final debe ser igual a la cantidad aceptada.', 16, 1);
            RETURN;
        END

        -- UPSERT: actualiza si ya existe, inserta si no
        IF EXISTS (
            SELECT 1 FROM plh.plh_prh_proceso_horneado_detalle
            WHERE prh_codigo_neg          = @CodigoNeg
              AND prh_tienda_codigo       = @TiendaCodigo
              AND prh_fecha               = @Fecha
              AND prh_pro_codigo          = @ProCodigo
              AND prh_hor_numero_secuencia = @HorNumeroSecuencia
        )
        BEGIN
            UPDATE plh.plh_prh_proceso_horneado_detalle
            SET prh_cantidad_aceptada      = @CantidadAceptada,
                prh_cantidad_rechazada     = @CantidadRechazada,
                prh_motivo_rechazo         = @MotivoRechazo,
                prh_cantidad_final         = @CantidadFinal,
                prh_usuario_registro_codigo = @UsuarioCodigo
            WHERE prh_codigo_neg          = @CodigoNeg
              AND prh_tienda_codigo       = @TiendaCodigo
              AND prh_fecha               = @Fecha
              AND prh_pro_codigo          = @ProCodigo
              AND prh_hor_numero_secuencia = @HorNumeroSecuencia;
        END
        ELSE
        BEGIN
            INSERT INTO plh.plh_prh_proceso_horneado_detalle (
                prh_codigo_neg, prh_tienda_codigo, prh_fecha,
                prh_pro_codigo, prh_hor_numero_secuencia,
                prh_cantidad_aceptada, prh_cantidad_rechazada,
                prh_motivo_rechazo, prh_cantidad_final,
                prh_fecha_registro, prh_usuario_registro_codigo
            )
            VALUES (
                @CodigoNeg, @TiendaCodigo, @Fecha,
                @ProCodigo, @HorNumeroSecuencia,
                @CantidadAceptada, @CantidadRechazada,
                @MotivoRechazo, @CantidadFinal,
                GETDATE(), @UsuarioCodigo
            );
        END

        UPDATE plh.plh_prh_proceso_horneado_encabezado
        SET prh_estado_fermentacion          = 3,
            prh_revisado                     = 1,
            prh_fecha_revision               = GETDATE(),
            prh_usuario_revision_codigo      = @UsuarioCodigo,
            prh_observaciones                = ISNULL(@Observaciones, prh_observaciones),
            prh_fecha_actualizacion          = GETDATE(),
            prh_usuario_actualizacion_codigo = @UsuarioCodigo
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_pro_codigo          = @ProCodigo
          AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

        -- tip_id 5 = RESULTADO_REGISTRADO
        INSERT INTO plh.plh_trz_trazabilidad (
            trz_prh_codigo_neg, trz_prh_tienda_codigo, trz_prh_fecha,
            trz_prh_pro_codigo, trz_prh_hor_numero_secuencia,
            trz_tip_id, trz_fecha_evento, trz_usuario_codigo, trz_observaciones
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @Fecha,
            @ProCodigo, @HorNumeroSecuencia,
            5, GETDATE(), @UsuarioCodigo,
            CONCAT('Aceptada:', CAST(@CantidadAceptada AS INT),
                   ' Rechazada:', CAST(@CantidadRechazada AS INT),
                   CASE WHEN @MotivoRechazo IS NOT NULL THEN CONCAT(' Motivo:', @MotivoRechazo) ELSE '' END,
                   ' Final:', CAST(@CantidadFinal AS INT))
        );

        COMMIT TRANSACTION;

        SELECT @CodigoNeg AS prh_codigo_neg, @TiendaCodigo AS prh_tienda_codigo,
               @Fecha AS prh_fecha, @ProCodigo AS prh_pro_codigo,
               @HorNumeroSecuencia AS prh_hor_numero_secuencia;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_prh_MarcarRevisado]
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

    UPDATE plh.plh_prh_proceso_horneado_encabezado
    SET prh_revisado                     = @Revisado,
        prh_fecha_revision               = CASE WHEN @Revisado = 1 THEN GETDATE() ELSE NULL END,
        prh_usuario_revision_codigo      = CASE WHEN @Revisado = 1 THEN @UsuarioCodigo ELSE NULL END,
        prh_fecha_actualizacion          = GETDATE(),
        prh_usuario_actualizacion_codigo = @UsuarioCodigo
    WHERE prh_codigo_neg          = @CodigoNeg
      AND prh_tienda_codigo       = @TiendaCodigo
      AND prh_fecha               = @Fecha
      AND prh_pro_codigo          = @ProCodigo
      AND prh_hor_numero_secuencia = @HorNumeroSecuencia;

    IF @@ROWCOUNT = 0
        RAISERROR('Encabezado no encontrado.', 16, 1);
END;
GO
