-- =============================================
-- Módulo: Control de Repostería (Formato de Rotación)
-- SPs: plh_rot_RegistrarRotacion, plh_rot_CerrarFinal, plh_rot_CerrarDia
-- Base de datos: sm_backoffice_op
-- Estados prc_estado_rotacion: 0=PENDIENTE, 1=FINAL_CERRADO, 2=CERRADO
-- =============================================

USE [sm_backoffice_op];
GO

-- =============================================
-- UPSERT de cantidad final en Control de Repostería.
-- Líneas normales: MERGE por fecha+tienda+producto+horneada.
-- Transferencias (EsTransferencia=1): siempre INSERT, rot_hor_numero_secuencia queda NULL.
-- =============================================
CREATE OR ALTER PROCEDURE [plh].[plh_rot_RegistrarRotacion]
    @CodigoNeg          NVARCHAR(10),
    @TiendaCodigo       INT,
    @Fecha              DATE,
    @ProCodigo          NVARCHAR(50),
    @HorNumeroSecuencia INT          = NULL,
    @CantidadFinal      DECIMAL(10,2),
    @EsTransferencia    BIT          = 0,
    @UsuarioCodigo      NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsTransferencia = 0
    BEGIN
        MERGE plh.plh_rot_rotacion AS target
        USING (SELECT @CodigoNeg, @TiendaCodigo, @Fecha, @ProCodigo, @HorNumeroSecuencia) AS src
            (src_codigo_neg, src_tienda, src_fecha, src_pro, src_hor)
        ON (target.rot_codigo_neg         = src_codigo_neg
            AND target.rot_tienda_codigo  = src_tienda
            AND target.rot_fecha          = src_fecha
            AND target.rot_pro_codigo     = src_pro
            AND target.rot_hor_numero_secuencia = src_hor)
        WHEN MATCHED THEN
            UPDATE SET rot_cantidad_final          = @CantidadFinal,
                       rot_usuario_registro_codigo = @UsuarioCodigo,
                       rot_fecha_registro          = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (rot_codigo_neg, rot_tienda_codigo, rot_fecha, rot_pro_codigo,
                    rot_hor_numero_secuencia, rot_cantidad_final, rot_es_transferencia,
                    rot_fecha_registro, rot_usuario_registro_codigo)
            VALUES (@CodigoNeg, @TiendaCodigo, @Fecha, @ProCodigo,
                    @HorNumeroSecuencia, @CantidadFinal, 0,
                    GETDATE(), @UsuarioCodigo);

        SELECT rot_id
        FROM plh.plh_rot_rotacion
        WHERE rot_codigo_neg          = @CodigoNeg
          AND rot_tienda_codigo       = @TiendaCodigo
          AND rot_fecha               = @Fecha
          AND rot_pro_codigo          = @ProCodigo
          AND rot_hor_numero_secuencia = @HorNumeroSecuencia;
        RETURN;
    END

    -- Transferencias: siempre INSERT
    INSERT INTO plh.plh_rot_rotacion
        (rot_codigo_neg, rot_tienda_codigo, rot_fecha, rot_pro_codigo,
         rot_hor_numero_secuencia, rot_cantidad_final, rot_es_transferencia,
         rot_fecha_registro, rot_usuario_registro_codigo)
    VALUES
        (@CodigoNeg, @TiendaCodigo, @Fecha, @ProCodigo,
         NULL, @CantidadFinal, 1,
         GETDATE(), @UsuarioCodigo);

    SELECT SCOPE_IDENTITY() AS rot_id;
END;
GO

-- =============================================
-- Cierra las cantidades finales del día (estado 1 = FINAL_CERRADO).
-- Bloquea inputs de cantidad final. DEVO sigue editable.
-- Requiere que el proceso exista y esté en estado 0 (PENDIENTE).
-- =============================================
CREATE OR ALTER PROCEDURE [plh].[plh_rot_CerrarFinal]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_fecha         = @Fecha
          AND prc_tienda_codigo = @TiendaCodigo
          AND prc_codigo_neg    = @CodigoNeg
    )
    BEGIN
        RAISERROR('No existe proceso para esta fecha y tienda.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_fecha           = @Fecha
          AND prc_tienda_codigo   = @TiendaCodigo
          AND prc_codigo_neg      = @CodigoNeg
          AND prc_estado_rotacion >= 1
    )
    BEGIN
        RAISERROR('Las cantidades finales ya fueron cerradas para esta fecha y tienda.', 16, 1);
        RETURN;
    END

    -- Antes esta validación solo vivía en el frontend (botón deshabilitado mientras
    -- faltaba algún producto): un botón deshabilitado no es una garantía real — un
    -- estado stale, una condición de carrera con el guardado con debounce de Cantidad
    -- Final, u otro camino cualquiera hacia este SP podían cerrar con productos en
    -- blanco. Mismo criterio de "línea a completar" que usa GetRotacionesQueryHandler
    -- para pintar la pantalla: todo producto con control de repostería cuya horneada
    -- ya salió del horno (prh_fecha_fin_horneado NOT NULL) debe tener Cantidad Final.
    DECLARE @Faltantes INT;
    SELECT @Faltantes = COUNT(*)
    FROM plh.plh_prh_proceso_horneado_encabezado e
    INNER JOIN plh.plh_cat_catalogo_productos c
        ON  c.cat_pro_codigo    = e.prh_pro_codigo
        AND c.cat_codigo_neg    = e.prh_codigo_neg
        AND c.cat_tienda_codigo IN (0, e.prh_tienda_codigo)
    WHERE e.prh_codigo_neg               = @CodigoNeg
      AND e.prh_tienda_codigo            = @TiendaCodigo
      AND e.prh_fecha                    = @Fecha
      AND e.prh_fecha_fin_horneado       IS NOT NULL
      AND c.cat_aplica_control_reposteria = 1
      AND NOT EXISTS (
            SELECT 1 FROM plh.plh_rot_rotacion r
            WHERE r.rot_codigo_neg           = e.prh_codigo_neg
              AND r.rot_tienda_codigo        = e.prh_tienda_codigo
              AND r.rot_fecha                = e.prh_fecha
              AND r.rot_pro_codigo           = e.prh_pro_codigo
              AND r.rot_hor_numero_secuencia = e.prh_hor_numero_secuencia
              AND r.rot_es_transferencia     = 0
              AND r.rot_cantidad_final       IS NOT NULL
      );

    IF @Faltantes > 0
    BEGIN
        RAISERROR('No se puede cerrar: faltan %d producto(s) sin Cantidad Final registrada para esta fecha.', 16, 1, @Faltantes);
        RETURN;
    END

    UPDATE plh.plh_prc_procesos
    SET prc_estado_rotacion      = 1,
        prc_fecha_cierre_final   = GETDATE(),
        prc_usuario_cierre_final = @UsuarioCodigo
    WHERE prc_fecha         = @Fecha
      AND prc_tienda_codigo = @TiendaCodigo
      AND prc_codigo_neg    = @CodigoNeg;
END;
GO

-- =============================================
-- Cierra la DEVO del día (estado 2 = CERRADO).
-- Bloquea todo. Requiere que las cantidades finales ya estén cerradas (estado >= 1).
-- =============================================
CREATE OR ALTER PROCEDURE [plh].[plh_rot_CerrarDia]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @Fecha          DATE,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_fecha         = @Fecha
          AND prc_tienda_codigo = @TiendaCodigo
          AND prc_codigo_neg    = @CodigoNeg
    )
    BEGIN
        RAISERROR('No existe proceso para esta fecha y tienda.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_fecha           = @Fecha
          AND prc_tienda_codigo   = @TiendaCodigo
          AND prc_codigo_neg      = @CodigoNeg
          AND prc_estado_rotacion >= 1
    )
    BEGIN
        RAISERROR('Debes cerrar las cantidades finales antes de cerrar la DEVO.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM plh.plh_prc_procesos
        WHERE prc_fecha           = @Fecha
          AND prc_tienda_codigo   = @TiendaCodigo
          AND prc_codigo_neg      = @CodigoNeg
          AND prc_estado_rotacion = 2
    )
    BEGIN
        RAISERROR('La DEVO ya fue cerrada para esta fecha y tienda.', 16, 1);
        RETURN;
    END

    UPDATE plh.plh_prc_procesos
    SET prc_estado_rotacion         = 2,
        prc_fecha_cierre_rotacion   = GETDATE(),
        prc_usuario_cierre_rotacion = @UsuarioCodigo
    WHERE prc_fecha         = @Fecha
      AND prc_tienda_codigo = @TiendaCodigo
      AND prc_codigo_neg    = @CodigoNeg;
END;
GO
