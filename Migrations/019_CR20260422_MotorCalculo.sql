-- =============================================
-- Migration 019: Motor de Cálculo
-- Tablas: plh_fct_factor_sku, plh_pha_patron_horario
-- =============================================

USE [sm_backoffice_op];
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Factor mensual por tienda-SKU
    CREATE TABLE [plh].[plh_fct_factor_sku] (
        fct_codigo_neg          NVARCHAR(10)    NOT NULL,
        fct_tienda_codigo       INT             NOT NULL,
        fct_id                  BIGINT          IDENTITY(1,1) NOT NULL,
        fct_pro_codigo          NVARCHAR(50)    NOT NULL,
        fct_anio_proyectado     INT             NOT NULL,
        fct_mes_proyectado      INT             NOT NULL,
        fct_anio_referencia     INT             NOT NULL,
        fct_mes_referencia      INT             NOT NULL,
        fct_factor_sku          DECIMAL(18,6)   NOT NULL,
        fct_fecha_calculo       DATETIME        NOT NULL CONSTRAINT DF_fct_fecha_calculo DEFAULT GETDATE(),
        fct_usuario_calculo     NVARCHAR(50)    NOT NULL,

        CONSTRAINT PK_plh_fct_factor_sku PRIMARY KEY (fct_codigo_neg, fct_tienda_codigo, fct_id),
        CONSTRAINT UQ_fct_tienda_sku_mes UNIQUE (
            fct_codigo_neg, fct_tienda_codigo, fct_pro_codigo,
            fct_anio_proyectado, fct_mes_proyectado
        )
    );

    -- Patrón horario promedio por tienda-día-hora
    CREATE TABLE [plh].[plh_pha_patron_horario] (
        pha_codigo_neg          NVARCHAR(10)    NOT NULL,
        pha_tienda_codigo       INT             NOT NULL,
        pha_id                  BIGINT          IDENTITY(1,1) NOT NULL,
        pha_anio_proyectado     INT             NOT NULL,
        pha_mes_proyectado      INT             NOT NULL,
        pha_dia_semana          TINYINT         NOT NULL,   -- 1=Lunes … 7=Domingo
        pha_hora                TINYINT         NOT NULL,   -- 0-23
        pha_porcentaje          DECIMAL(8,6)    NOT NULL,   -- 0.000000 a 1.000000
        pha_fecha_calculo       DATETIME        NOT NULL CONSTRAINT DF_pha_fecha_calculo DEFAULT GETDATE(),
        pha_usuario_calculo     NVARCHAR(50)    NOT NULL,

        CONSTRAINT PK_plh_pha_patron_horario PRIMARY KEY (pha_codigo_neg, pha_tienda_codigo, pha_id),
        CONSTRAINT UQ_pha_tienda_mes_dia_hora UNIQUE (
            pha_codigo_neg, pha_tienda_codigo,
            pha_anio_proyectado, pha_mes_proyectado,
            pha_dia_semana, pha_hora
        )
    );

    COMMIT TRANSACTION;
    PRINT 'Migration 019: Motor de Cálculo completada exitosamente.';
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
