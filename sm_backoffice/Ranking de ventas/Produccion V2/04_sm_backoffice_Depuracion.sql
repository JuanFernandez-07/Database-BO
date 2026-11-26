-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███
-- PRODUCCIÓN V2 · Paso 4 de 4 · Depuración. NO correr junto con los pasos 1-3: correr cuando el
-- job único lleve unos días validado y la API ya esté publicada con la versión de bloques (deja de
-- leer vta.rvt_cpr_control_proceso).
-- Idempotente: lo que ya no existe se salta.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Borra lo que solo usaban los jobs de la versión anterior (borrados en el paso 1):
--   vta.rvd_ActualizarResumenIncremental  incremental de FiscalInvoice/RankingGNDSALE
--   vta.rvd_RecalcularResumenRango        recálculo de 7 días
--   vta.rvd_CompletarPropinaPendiente     propina tardía de FiscalInvoice
--   vta.rvd_RecalcularDias                lo llamaban los tres anteriores
--   vta.rvd_ImportarVentaDesdeKIO         reemplazado por vta.rvd_ImportarVentaRanking
--   vta.rvt_cpr_control_proceso           marcas de agua del incremental
--   vta.rvd_tienda_dia                    tipo tabla de rvd_RecalcularDias
-- Se QUEDAN (los usa el LY hasta tener un año de bloques): vta.vw_rvd_venta_neta,
-- vta.vw_rvd_fiscal_invoice_neto, vta.vw_rvd_gndsale_neto, vta.rvd_FechaCorteKIO.

USE sm_backoffice;
GO

-- Verificación previa: ningún job ni SP vivo debe llamar a lo que se borra. 0 filas.
SELECT OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS objeto_que_lo_usa
FROM sys.sql_modules m
WHERE (m.definition LIKE '%rvd_RecalcularDias%'
    OR m.definition LIKE '%rvt_cpr_control_proceso%'
    OR m.definition LIKE '%rvd_ImportarVentaDesdeKIO%')
  AND OBJECT_NAME(m.object_id) NOT IN ('rvd_ActualizarResumenIncremental', 'rvd_RecalcularResumenRango',
                                       'rvd_CompletarPropinaPendiente', 'rvd_RecalcularDias',
                                       'rvd_ImportarVentaDesdeKIO')
UNION ALL
SELECT N'job: ' + j.name
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
WHERE s.command LIKE '%rvd_ActualizarResumenIncremental%'
   OR s.command LIKE '%rvd_RecalcularResumenRango%'
   OR s.command LIKE '%rvd_CompletarPropinaPendiente%'
   OR s.command LIKE '%rvd_ImportarVentaDesdeKIO%';
GO

DROP PROCEDURE IF EXISTS vta.rvd_ActualizarResumenIncremental;
DROP PROCEDURE IF EXISTS vta.rvd_RecalcularResumenRango;
DROP PROCEDURE IF EXISTS vta.rvd_CompletarPropinaPendiente;
DROP PROCEDURE IF EXISTS vta.rvd_RecalcularDias;
DROP PROCEDURE IF EXISTS vta.rvd_ImportarVentaDesdeKIO;
DROP TABLE IF EXISTS vta.rvt_cpr_control_proceso;
GO

IF TYPE_ID('vta.rvd_tienda_dia') IS NOT NULL
    DROP TYPE vta.rvd_tienda_dia;
GO

-- Verificación: 0 filas.
SELECT name, type_desc
FROM sys.objects
WHERE SCHEMA_NAME(schema_id) = 'vta'
  AND name IN ('rvd_ActualizarResumenIncremental', 'rvd_RecalcularResumenRango', 'rvd_CompletarPropinaPendiente',
               'rvd_RecalcularDias', 'rvd_ImportarVentaDesdeKIO', 'rvt_cpr_control_proceso');
GO

-- ─── Opcional (sm_pos) ──────────────────────────────────────────────────────────────
-- El trigger de propina de FiscalInvoice (Produccion/05) ya no alimenta el ranking: desde el corte
-- la propina de GT/SV llega por KIO. Los valores ya guardados en FiscalInvoice.Propina se quedan
-- (los usa el LY). Para quitarlo:
-- USE sm_pos;
-- DROP TRIGGER IF EXISTS dbo.trg_FiscalInvoice_Propina;
