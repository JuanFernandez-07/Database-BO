-- =============================================
-- Migration 012: Tabla de cierres de día — Control de Repostería
-- Requerimiento: Registrar cuando el supervisor cierra el control del día
-- Script idempotente: seguro de re-ejecutar
-- =============================================

IF NOT EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID('plh.plh_rot_cierres_dia')
)
BEGIN
    CREATE TABLE plh.plh_rot_cierres_dia (
        cdi_id              BIGINT IDENTITY PRIMARY KEY,
        cdi_fecha           DATE NOT NULL,
        cdi_tienda_codigo   INT NOT NULL,
        cdi_codigo_neg      NVARCHAR(20) NOT NULL,
        cdi_fecha_cierre    DATETIME NOT NULL DEFAULT GETDATE(),
        cdi_usuario_codigo  NVARCHAR(50) NOT NULL,
        CONSTRAINT UQ_cdi_fecha_tienda UNIQUE (cdi_fecha, cdi_tienda_codigo, cdi_codigo_neg)
    );
END
GO
