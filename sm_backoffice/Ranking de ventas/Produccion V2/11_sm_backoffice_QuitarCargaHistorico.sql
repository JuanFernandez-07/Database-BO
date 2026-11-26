-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_backoffice ███
-- Ranking de Ventas · Quitar la carga del histórico.
-- Idempotente: se puede volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- El histórico de fechas especiales ya está cargado en vta.rvt_rvd_resumen_venta_diaria y no se borra.
-- Si hiciera falta otro día pasado, se carga desde Aloha on premise.
-- Con esto el Ranking deja de depender de sm_pos.dbo.FiscalInvoice y sm_pos.dbo.RankingGNDSALE:
-- vta.rvd_CargarHistoricoFecha era el único objeto que las leía (como respaldo).
--
-- Se borra:  vta.rvd_CargarHistoricoFecha
-- No cambia: rvd_ImportarVentaRanking (job de cada 15 min), rvd_Documentos*, rvd_GuardarDocumentos,
--            rvd_ReintentarDiasPendientes, tablas, funciones y vista.
-- Quedan 13 objetos.

USE sm_backoffice;
GO

-- ─── 0. Verificación previa: nadie más lo llama ─────────────────────────────────────
DECLARE @error NVARCHAR(4000) = (
    SELECT TOP (1) motivo FROM (
        SELECT N'Lo referencia el objeto ' + OBJECT_SCHEMA_NAME(m.object_id) + N'.' + OBJECT_NAME(m.object_id) AS motivo
        FROM sys.sql_modules m
        WHERE m.definition LIKE N'%rvd_CargarHistoricoFecha%'
          AND m.object_id <> ISNULL(OBJECT_ID('vta.rvd_CargarHistoricoFecha', 'P'), 0)
          -- rvd_ImportarVentaRanking solo lo menciona en un mensaje de error; no lo llama.
          AND m.object_id <> ISNULL(OBJECT_ID('vta.rvd_ImportarVentaRanking', 'P'), 0)
        UNION ALL
        SELECT N'Lo llama el paso "' + s.step_name + N'" del job "' + j.name + N'"'
        FROM msdb.dbo.sysjobsteps s
        JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
        WHERE s.command LIKE N'%rvd_CargarHistoricoFecha%'
    ) x
);
IF @error IS NOT NULL
BEGIN
    RAISERROR(N'%s. No se borró nada.', 16, 1, @error);
    SET NOEXEC ON;
END;
GO

-- ─── 1. Borrar ──────────────────────────────────────────────────────────────────────
DROP PROCEDURE IF EXISTS vta.rvd_CargarHistoricoFecha;
GO

SET NOEXEC OFF;
GO

-- ─── 2. Verificación ────────────────────────────────────────────────────────────────
-- 2.1 Debe devolver NULL.
SELECT OBJECT_ID('vta.rvd_CargarHistoricoFecha', 'P') AS cargar_historico;

-- 2.2 Ningún objeto del Ranking lee FiscalInvoice ni RankingGNDSALE. Debe devolver 0 filas.
SELECT OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS objeto
FROM sys.sql_modules m
WHERE OBJECT_SCHEMA_NAME(m.object_id) = 'vta'
  AND (m.definition LIKE N'%sm_pos.dbo.FiscalInvoice%' OR m.definition LIKE N'%sm_pos.dbo.RankingGNDSALE%');

-- 2.3 El histórico sigue cargado (debe salir cada fecha con sus tiendas).
SELECT rvd_fecha, COUNT(DISTINCT rvd_codigo_tie) AS tiendas
FROM vta.vw_rvd_resumen_ultimo_bloque
WHERE rvd_fecha IN ('2025-12-24', '2025-12-31', '2026-01-06', '2026-02-14', '2026-05-10', '2026-09-15')
GROUP BY rvd_fecha
ORDER BY rvd_fecha;

-- 2.4 Objetos del Ranking: deben quedar 13.
SELECT o.type_desc, COUNT(*) AS objetos
FROM sys.objects o
WHERE o.schema_id = SCHEMA_ID('vta')
  AND (o.name LIKE 'rvd[_]%' OR o.name LIKE 'rvt[_]%' OR o.name LIKE 'vw[_]rvd[_]%')
  AND o.type IN ('U', 'P', 'FN', 'IF', 'TF', 'V')
GROUP BY o.type_desc;
GO
