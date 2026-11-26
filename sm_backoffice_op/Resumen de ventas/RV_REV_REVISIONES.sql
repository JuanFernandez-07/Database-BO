-- Ejecutar en la base sm_backoffice_op
-- Tabla para "marcar como revisado" (Gerente / Contabilidad) del módulo Resumen de Ventas.
-- No usa migraciones de EF Core (igual que el resto de Plan de Hornos) — se crea con script directo.

CREATE SCHEMA rv;
GO

CREATE TABLE rv.rv_rev_revisiones (
    rev_id                     BIGINT IDENTITY(1,1) PRIMARY KEY,
    rev_tienda_codigo          INT             NOT NULL,
    rev_codigo_neg             NVARCHAR(10)    NOT NULL,
    rev_fecha                  DATE            NOT NULL,
    rev_rol                    NVARCHAR(20)    NOT NULL,  -- 'gerente' | 'contabilidad'
    rev_revisado_por_codigo    NVARCHAR(20)    NOT NULL,
    rev_fecha_revision         DATETIME2       NOT NULL,
    CONSTRAINT UQ_rv_rev_revisiones UNIQUE (rev_tienda_codigo, rev_codigo_neg, rev_fecha, rev_rol)
);
GO
