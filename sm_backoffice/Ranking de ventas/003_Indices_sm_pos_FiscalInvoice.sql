-- Ejecutar en la base sm_pos — SOLO con autorización de quien administra sm_pos / el importador.
-- sm_pos.dbo.FiscalInvoice no tiene ningún índice (verificado 2026-10-14). Recibe ~42 mil filas
-- por día; sin estos índices cada ejecución del incremental del Ranking de Ventas recorre la
-- tabla completa.

USE sm_pos;
GO

-- Para detectar lo nuevo: WHERE FechaImportacion >= @desde
CREATE INDEX IX_FiscalInvoice_FechaImportacion
    ON dbo.FiscalInvoice (FechaImportacion)
    INCLUDE (LC_UNIT, LC_DOB, DocTypeId);
GO

-- Para recalcular un (tienda, día) completo
CREATE INDEX IX_FiscalInvoice_Dob_Unit
    ON dbo.FiscalInvoice (LC_DOB, LC_UNIT)
    INCLUDE (DocTypeId, TermId, TaxableAmount, TotalTax, TotalTxn);
GO
