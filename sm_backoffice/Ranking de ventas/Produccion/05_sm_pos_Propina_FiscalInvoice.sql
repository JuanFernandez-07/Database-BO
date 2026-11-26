-- ════════════════════════════════════════════════════════════════════════════════════
-- PRODUCCIÓN · Propina · Base: sm_pos
-- Guarda en sm_pos.dbo.FiscalInvoice.Propina la propina de cada factura. Correr ANTES del paso 1
-- (01 verifica que exista la columna y su vista la usa).
-- Es idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Origen: ALOHA.dbo.GNDITEM (mismo servidor), ITEM 999323, columna DISCPRIC.
-- Cruce:  GNDITEM.LC_UNIT = FiscalInvoice.LC_UNIT, LC_DOB = LC_DOB, [CHECK] = CheckNumber.
--
-- Valor de FiscalInvoice.Propina:
--   * monto  -> el check está en GNDITEM y tiene línea(s) 999323 (se suman).
--   * 0      -> el check está en GNDITEM y NO tiene línea 999323: no tuvo propina.
--   * NULL   -> el check todavía no está en GNDITEM (GNDITEM se llena con atraso respecto a la
--               importación de cada 15 min). Lo completa después vta.rvd_CompletarPropinaPendiente
--               (sm_backoffice, paso 1), que corre en los jobs del paso 3.
--   Supone que GNDITEM carga cada check completo (todas sus líneas a la vez). Si cargara un check a
--   medias, ese check podría quedar en 0 teniendo propina.
--
-- Por qué AFTER INSERT: SQL Server no tiene BEFORE INSERT. La alternativa INSTEAD OF INSERT obliga a
-- repetir todas las columnas de FiscalInvoice en el trigger y se rompe cuando se agrega una columna.
-- El trigger procesa todo el bloque que inserta usp_ImportarInvoiceDesdeKIOGT en un solo UPDATE y
-- ubica las filas por StoreFiscalId + GUID (índice IX_FiscalInvoice_StoreFiscalId_GUID).

USE sm_pos;
GO

-- ─── 1. Columna ─────────────────────────────────────────────────────────────────────
IF COL_LENGTH('dbo.FiscalInvoice', 'Propina') IS NULL
    ALTER TABLE dbo.FiscalInvoice ADD Propina DECIMAL(18, 2) NULL;
GO

-- ─── 2. Trigger ─────────────────────────────────────────────────────────────────────
CREATE OR ALTER TRIGGER dbo.trg_FiscalInvoice_Propina
ON dbo.FiscalInvoice
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- SUM sin filas = NULL (check aún no está en GNDITEM); con filas pero sin 999323 = 0.
    UPDATE fi
    SET fi.Propina = g.Propina
    FROM dbo.FiscalInvoice fi
    JOIN inserted i
      ON i.StoreFiscalId = fi.StoreFiscalId
     AND i.GUID = fi.GUID
    OUTER APPLY (
        SELECT SUM(CASE WHEN gi.ITEM = 999323 THEN gi.DISCPRIC ELSE 0 END) AS Propina
        FROM ALOHA.dbo.GNDITEM gi
        WHERE gi.LC_UNIT = fi.LC_UNIT
          AND gi.LC_DOB = fi.LC_DOB
          AND gi.[CHECK] = fi.CheckNumber
    ) g;
END;
GO

-- ─── 3. Una sola vez: dejar pendientes los 0 de hoy y ayer ──────────────────────────
-- Con la versión anterior del trigger, "no encontrado" se guardaba como 0. Esto los vuelve NULL para
-- que vta.rvd_CompletarPropinaPendiente los revise (los checks sin propina vuelven a quedar en 0).
-- Correr solo al instalar esta versión del trigger.
-- UPDATE dbo.FiscalInvoice
-- SET Propina = NULL
-- WHERE LC_DOB >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))
--   AND Propina = 0;
-- GO

-- ─── 4. Llenado de histórico (manual, por rango) ────────────────────────────────────
-- Para fechas cargadas antes de existir el trigger. Una semana por vuelta para no bloquear la
-- importación; se puede cancelar y volver a correr (salta lo ya llenado).
-- Ya ejecutado: 2025-10-22 a 2026-01-06 (enero 2026 sin datos en GNDITEM) y 2026-10-13 a 2026-10-28.
/*
DECLARE @ini DATE = '2025-10-22', @fin_total DATE = '2026-01-07', @fin DATE, @msg VARCHAR(50);

WHILE @ini < @fin_total
BEGIN
    SET @fin = DATEADD(DAY, 7, @ini);
    IF @fin > @fin_total SET @fin = @fin_total;

    DROP TABLE IF EXISTS #propina;

    SELECT g.LC_UNIT, g.LC_DOB, g.[CHECK],
           SUM(CASE WHEN g.ITEM = 999323 THEN g.DISCPRIC ELSE 0 END) AS Propina
    INTO #propina
    FROM ALOHA.dbo.GNDITEM g
    WHERE g.LC_DOB >= @ini AND g.LC_DOB < @fin
    GROUP BY g.LC_UNIT, g.LC_DOB, g.[CHECK];

    CREATE CLUSTERED INDEX IX_p ON #propina (LC_UNIT, LC_DOB, [CHECK]);

    UPDATE fi
    SET fi.Propina = p.Propina
    FROM dbo.FiscalInvoice fi
    JOIN #propina p
      ON p.LC_UNIT = fi.LC_UNIT AND p.LC_DOB = fi.LC_DOB AND p.[CHECK] = fi.CheckNumber
    WHERE fi.LC_DOB >= @ini AND fi.LC_DOB < @fin
      AND fi.Propina IS NULL;

    SET @msg = CONVERT(VARCHAR(10), @ini, 23) + ' listo';
    RAISERROR(@msg, 0, 1) WITH NOWAIT;

    SET @ini = @fin;
END;

DROP TABLE IF EXISTS #propina;
-- Después: EXEC sm_backoffice.vta.rvd_RecalcularResumenRango sobre el mismo rango.
*/

-- ─── 5. Verificación ────────────────────────────────────────────────────────────────
-- Por día: pendientes (NULL) deben ser pocos y solo en hoy/ayer.
SELECT TOP 10 LC_DOB,
       COUNT(*)                                         AS facturas,
       SUM(CASE WHEN Propina IS NULL THEN 1 ELSE 0 END) AS pendientes,
       SUM(CASE WHEN Propina > 0 THEN 1 ELSE 0 END)     AS con_propina,
       SUM(Propina)                                     AS total_propina
FROM dbo.FiscalInvoice
GROUP BY LC_DOB
ORDER BY LC_DOB DESC;
GO
