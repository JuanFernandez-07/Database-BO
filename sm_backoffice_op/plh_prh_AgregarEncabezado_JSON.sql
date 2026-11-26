-- =============================================
-- DESCARTADO — no está en uso. Se volvió a la versión fila-por-fila
-- (Backup_plh_prh_AgregarEncabezado_original.sql / Plan de hornos_V3/04_Proceso.sql,
-- ambas ya con el agregado de @EsExtraordinario para Pedido Extra). Este archivo queda
-- solo de referencia histórica del experimento con JSON/MERGE.
-- =============================================

-- =============================================
-- plh_prh_AgregarEncabezado — convertido a batch vía JSON.
-- Reemplaza el modo "una fila por llamada" por un solo MERGE que procesa
-- todo el arreglo de productos de una vez (pensado para Enviar Plan, que hoy
-- hace un round-trip por cada producto×horneada del plan).
--
-- Si algo sale mal, corre Backup_plh_prh_AgregarEncabezado_original.sql para
-- regresar al comportamiento anterior.
--
-- Cambios de comportamiento vs. el original:
--   - Antes: si la fila ya existía, tronaba con "El producto ya fue agregado...".
--   - Ahora: si la fila ya existe, la ACTUALIZA (upsert) en vez de fallar —
--     necesario para que un solo llamado cubra tanto insertar como actualizar,
--     que es justo lo que hoy hace el loop en dos pasos (Agregar / Actualizar).
--   - Firma distinta: ya no son parámetros de una sola fila, es @ProductosJson.
--
-- @EsExtraordinario (Pedido Extra, ver plan Fase 2 — "cada Pedido Extra es una
-- fila independiente"): la horneada reservada para Pedido Extra ya no es el
-- número fijo 999 — es un RANGO (900-999) por tienda/fecha. Cada llamada con
-- @EsExtraordinario=1 calcula el SIGUIENTE número libre del rango y lo usa
-- para TODAS las filas del batch (ignora el HorNumeroSecuencia que venga en
-- el JSON para esas filas), así que un segundo Pedido Extra del mismo
-- producto/día cae en una fila nueva e independiente en vez de pisar/reabrir
-- la anterior. sp_getapplock serializa el cálculo para evitar que dos envíos
-- simultáneos obtengan el mismo número.
--
-- Pendiente si esto queda: actualizar los llamadores en C#
--   - EnviarPlanCommandHandler.cs (arma el batch completo, un solo llamado)
--   - CreateHorneadaExtraordinariaCommandHandler.cs (arma un batch de 1+ productos)
--   - IProcesoRepository.AgregarEncabezadoSpAsync / ProcesoRepository (nueva firma)
-- No se toca plh_prh_ActualizarCantidadBolsas.
-- =============================================

USE [sm_backoffice_op];
GO

CREATE OR ALTER PROCEDURE [plh].[plh_prh_AgregarEncabezado]
    @CodigoNeg              NVARCHAR(20),
    @TiendaCodigo           INT,
    @Fecha                  DATE,
    @UsuarioCodigo          NVARCHAR(50),
    -- [{"ProCodigo":"PAN01","HorNumeroSecuencia":1,"CantidadBolsas":10.5,
    --   "RackAsignado":null,"Observaciones":null,"NumeroCheck":null}, ...]
    @ProductosJson          NVARCHAR(MAX),
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

    DECLARE @NuevoSeqExtra INT = NULL;

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

        SELECT @NuevoSeqExtra = ISNULL(MAX(prh_hor_numero_secuencia), 899) + 1
        FROM plh.plh_prh_proceso_horneado_encabezado
        WHERE prh_codigo_neg          = @CodigoNeg
          AND prh_tienda_codigo       = @TiendaCodigo
          AND prh_fecha               = @Fecha
          AND prh_hor_numero_secuencia BETWEEN 900 AND 999;

        IF @NuevoSeqExtra > 999
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Se alcanzó el máximo de Pedidos Extra para esta tienda y fecha.', 16, 1);
            RETURN;
        END
    END

    MERGE plh.plh_prh_proceso_horneado_encabezado AS tgt
    USING (
        SELECT
            j.ProCodigo,
            CASE WHEN @EsExtraordinario = 1 THEN @NuevoSeqExtra ELSE j.HorNumeroSecuencia END AS HorNumeroSecuencia,
            j.CantidadBolsas,
            j.RackAsignado, j.Observaciones, j.NumeroCheck,
            CASE WHEN cat.cat_requiere_fermentacion = 1 THEN 0 ELSE 2 END AS EstadoFermentacionInicialRaw
        FROM OPENJSON(@ProductosJson)
            WITH (
                ProCodigo          NVARCHAR(50)  '$.ProCodigo',
                HorNumeroSecuencia INT            '$.HorNumeroSecuencia',
                CantidadBolsas     DECIMAL(18,4) '$.CantidadBolsas',
                RackAsignado       NVARCHAR(50)  '$.RackAsignado',
                Observaciones      NVARCHAR(500) '$.Observaciones',
                NumeroCheck        NVARCHAR(50)  '$.NumeroCheck'
            ) j
        OUTER APPLY (
            SELECT TOP 1 cat_requiere_fermentacion
            FROM plh.plh_cat_catalogo_productos
            WHERE cat_pro_codigo    = j.ProCodigo
              AND cat_codigo_neg    = @CodigoNeg
              AND cat_tienda_codigo IN (0, @TiendaCodigo)
              AND cat_activo        = 1
            ORDER BY cat_tienda_codigo DESC
        ) cat
    ) AS src
    ON  tgt.prh_codigo_neg           = @CodigoNeg
    AND tgt.prh_tienda_codigo        = @TiendaCodigo
    AND tgt.prh_fecha                = @Fecha
    AND tgt.prh_pro_codigo           = src.ProCodigo
    AND tgt.prh_hor_numero_secuencia = src.HorNumeroSecuencia
    WHEN MATCHED THEN
        UPDATE SET prh_cantidad_bolsas = src.CantidadBolsas
    WHEN NOT MATCHED THEN
        INSERT (
            prh_codigo_neg, prh_tienda_codigo, prh_fecha,
            prh_pro_codigo, prh_hor_numero_secuencia, prh_cantidad_bolsas,
            prh_estado_fermentacion, prh_omitio_fermentacion,
            prh_rack_asignado, prh_observaciones, prh_numero_check,
            prh_fecha_actualizacion, prh_usuario_actualizacion_codigo
        )
        VALUES (
            @CodigoNeg, @TiendaCodigo, @Fecha,
            src.ProCodigo, src.HorNumeroSecuencia, src.CantidadBolsas,
            ISNULL(src.EstadoFermentacionInicialRaw, 0),
            CASE WHEN src.EstadoFermentacionInicialRaw = 2 THEN 1 ELSE 0 END,
            src.RackAsignado, src.Observaciones, src.NumeroCheck,
            GETDATE(), @UsuarioCodigo
        );

    IF @EsExtraordinario = 1
        COMMIT TRANSACTION;

    SELECT
        @CodigoNeg AS prh_codigo_neg,
        @TiendaCodigo AS prh_tienda_codigo,
        @Fecha AS prh_fecha,
        (SELECT COUNT(*) FROM OPENJSON(@ProductosJson)) AS filas_procesadas,
        @NuevoSeqExtra AS hor_numero_secuencia_asignado;
END;
GO
