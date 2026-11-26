-- =============================================
-- Módulo: Horneadas
-- SPs: plh_hor_GuardarHorneada, plh_hor_DesactivarHorneada, plh_hor_AsegurarRangoExtraordinario
-- Base de datos: sm_backoffice_op
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_hor_GuardarHorneada]
    @CodigoNeg                  NVARCHAR(20),
    @TiendaCodigo               INT,
    @NumeroSecuencia            INT,
    @HoraInicio                 TIME(0),
    @HoraFin                    TIME(0),
    @AplicaPedidoCocina         BIT,
    @Activa                     BIT,
    @SoloProductosDirectos      BIT,
    @UsuarioCodigo              NVARCHAR(50),
    @DiasAntesInicio            TINYINT = 0,
    @EsExtraordinaria           BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM plh.plh_hor_horneadas
        WHERE hor_codigo_neg       = @CodigoNeg
          AND hor_tienda_codigo    = @TiendaCodigo
          AND hor_numero_secuencia = @NumeroSecuencia
    )
    BEGIN
        INSERT INTO plh.plh_hor_horneadas (
            hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia,
            hor_hora_inicio, hor_hora_fin, hor_aplica_pedido_cocina,
            hor_activa, hor_solo_productos_directos, hor_dias_antes_inicio, hor_es_extraordinaria,
            hor_fecha_creacion, hor_usuario_creacion_codigo,
            hor_fecha_modificacion, hor_usuario_modificacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @NumeroSecuencia,
            @HoraInicio, @HoraFin, @AplicaPedidoCocina,
            @Activa, @SoloProductosDirectos, @DiasAntesInicio, @EsExtraordinaria,
            GETDATE(), @UsuarioCodigo,
            GETDATE(), @UsuarioCodigo
        );
    END
    ELSE
    BEGIN
        UPDATE plh.plh_hor_horneadas
        SET hor_hora_inicio                 = @HoraInicio,
            hor_hora_fin                    = @HoraFin,
            hor_aplica_pedido_cocina        = @AplicaPedidoCocina,
            hor_activa                      = @Activa,
            hor_solo_productos_directos     = @SoloProductosDirectos,
            hor_dias_antes_inicio           = @DiasAntesInicio,
            hor_es_extraordinaria           = @EsExtraordinaria,
            hor_fecha_modificacion          = GETDATE(),
            hor_usuario_modificacion_codigo = @UsuarioCodigo
        WHERE hor_codigo_neg       = @CodigoNeg
          AND hor_tienda_codigo    = @TiendaCodigo
          AND hor_numero_secuencia = @NumeroSecuencia;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Horneada no encontrada.', 16, 1);
            RETURN;
        END
    END

    INSERT INTO plh.plh_log_parametrizacion (
        log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia,
        log_usuario_codigo, log_fecha_hora, log_campo_modificado,
        log_valor_anterior, log_valor_nuevo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @NumeroSecuencia,
        @UsuarioCodigo, GETDATE(), 'UPSERT',
        NULL, CONCAT('SEQ:', @NumeroSecuencia, ' INICIO:', @HoraInicio, ' FIN:', @HoraFin)
    );

    SELECT @CodigoNeg AS hor_codigo_neg, @TiendaCodigo AS hor_tienda_codigo, @NumeroSecuencia AS hor_numero_secuencia;
END;
GO

-- =============================================

CREATE OR ALTER PROCEDURE [plh].[plh_hor_DesactivarHorneada]
    @CodigoNeg          NVARCHAR(20),
    @TiendaCodigo       INT,
    @NumeroSecuencia    INT,
    @UsuarioCodigo      NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE plh.plh_hor_horneadas
    SET hor_activa                      = 0,
        hor_fecha_modificacion          = GETDATE(),
        hor_usuario_modificacion_codigo = @UsuarioCodigo
    WHERE hor_codigo_neg       = @CodigoNeg
      AND hor_tienda_codigo    = @TiendaCodigo
      AND hor_numero_secuencia = @NumeroSecuencia;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Horneada no encontrada.', 16, 1);
        RETURN;
    END

    INSERT INTO plh.plh_log_parametrizacion (
        log_codigo_neg, log_tienda_codigo, log_hor_numero_secuencia,
        log_usuario_codigo, log_fecha_hora, log_campo_modificado,
        log_valor_anterior, log_valor_nuevo
    )
    VALUES (
        @CodigoNeg, @TiendaCodigo, @NumeroSecuencia,
        @UsuarioCodigo, GETDATE(), 'hor_activa',
        '1', '0'
    );
END;
GO

-- =============================================
-- Pedido Extra (rango 900-999): FK_prh_hor exige que exista una fila en
-- plh_hor_horneadas para CUALQUIER número usado como prh_hor_numero_secuencia.
-- Pre-crea (idempotente, solo las que falten) todo el rango 900-998 como placeholders
-- INACTIVOS — nunca deben aparecer como tabs en Proceso de Hornos (eso lo sigue
-- cubriendo únicamente el 999, activo, vía plh_hor_GuardarHorneada de siempre) ni en
-- Parametrización (que ya excluye hor_es_extraordinaria=1 sin importar hor_activa).
-- Sin entrada en plh_log_parametrizacion a propósito: son placeholders de sistema, no
-- cambios de configuración que alguien hizo.
-- =============================================
CREATE OR ALTER PROCEDURE [plh].[plh_hor_AsegurarRangoExtraordinario]
    @CodigoNeg      NVARCHAR(20),
    @TiendaCodigo   INT,
    @UsuarioCodigo  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Numeros AS (
        SELECT 900 AS n
        UNION ALL
        SELECT n + 1 FROM Numeros WHERE n < 998
    )
    INSERT INTO plh.plh_hor_horneadas (
        hor_codigo_neg, hor_tienda_codigo, hor_numero_secuencia,
        hor_hora_inicio, hor_hora_fin, hor_aplica_pedido_cocina,
        hor_activa, hor_solo_productos_directos, hor_dias_antes_inicio, hor_es_extraordinaria,
        hor_fecha_creacion, hor_usuario_creacion_codigo,
        hor_fecha_modificacion, hor_usuario_modificacion_codigo
    )
    SELECT
        @CodigoNeg, @TiendaCodigo, n.n,
        '00:00:00', '00:00:00', 0,
        0, 0, 0, 1,
        GETDATE(), @UsuarioCodigo,
        GETDATE(), @UsuarioCodigo
    FROM Numeros n
    WHERE NOT EXISTS (
        SELECT 1 FROM plh.plh_hor_horneadas h
        WHERE h.hor_codigo_neg       = @CodigoNeg
          AND h.hor_tienda_codigo    = @TiendaCodigo
          AND h.hor_numero_secuencia = n.n
    )
    OPTION (MAXRECURSION 100);
END;
GO
