-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ REEMPLAZADO POR "Produccion V2" (job único). NO volver a ejecutar: estos jobs se borran en V2/01.
-- ════════════════════════════════════════════════════════════════════════════════════
-- PRODUCCIÓN · Paso 3 de 5 · Base: msdb (SQL Server Agent del servidor de sm_backoffice)
-- Jobs del Ranking de Ventas. Requiere el paso 1.
--   Job 1: incremental cada 15 minutos + completar propina pendiente de hoy y ayer.
--   Job 2: red de seguridad diaria a las 02:00 — completa propina pendiente de 7 días y recalcula
--          completos los últimos 7 días.
-- Idempotente: si los jobs ya existen, los borra y los vuelve a crear.
-- El job corre con el dueño del SQL Agent: ese usuario necesita leer sm_pos.dbo.FiscalInvoice,
-- sm_pos.dbo.RankingGNDSALE y ALOHA.dbo.GNDITEM, actualizar sm_pos.dbo.FiscalInvoice (propina) y
-- escribir en sm_backoffice (normalmente ya es sysadmin).
-- ════════════════════════════════════════════════════════════════════════════════════

USE msdb;
GO

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Resumen venta diaria (incremental)')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Resumen venta diaria (incremental)', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)', @delete_unused_schedule = 1;
GO

-- ─── Job 1: incremental ─────────────────────────────────────────────────────────────
EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @description = N'Ranking de Ventas: actualiza vta.rvt_rvd_resumen_venta_diaria con lo nuevo de sm_pos (FiscalInvoice y RankingGNDSALE).';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @step_name = N'Actualizar incremental',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'EXEC vta.rvd_ActualizarResumenIncremental;',
    @on_success_action = 3;      -- siguiente paso

-- Propina que no estaba en GNDITEM al importar la factura (ver 05_sm_pos_Propina_FiscalInvoice.sql).
EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @step_name = N'Completar propina pendiente',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'EXEC vta.rvd_CompletarPropinaPendiente @dias_atras = 1;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Ranking ventas - cada 15 minutos',
    @freq_type = 4,              -- diario
    @freq_interval = 1,
    @freq_subday_type = 4,       -- minutos
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @schedule_name = N'Ranking ventas - cada 15 minutos';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)';
GO

-- ─── Job 2: recálculo diario de los últimos 7 días ──────────────────────────────────
EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @description = N'Ranking de Ventas: red de seguridad — recalcula completos los últimos 7 días del resumen.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @step_name = N'Completar propina pendiente 7 dias',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'EXEC vta.rvd_CompletarPropinaPendiente @dias_atras = 7;',
    @on_success_action = 3,      -- siguiente paso
    @on_fail_action = 3;         -- aunque falle, recalcular igual

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @step_name = N'Recalcular ultimos 7 dias',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'DECLARE @fin DATE = CAST(GETDATE() AS DATE);
DECLARE @ini DATE = DATEADD(DAY, -7, @fin);
EXEC vta.rvd_RecalcularResumenRango @fecha_ini = @ini, @fecha_fin = @fin;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Ranking ventas - diario 02:00',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 20000;  -- 02:00:00

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @schedule_name = N'Ranking ventas - diario 02:00';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)';
GO

-- ─── Verificación: ambos habilitados y con próxima ejecución ────────────────────────
SELECT j.name AS job, j.enabled AS habilitado, ja.next_scheduled_run_date AS proxima_ejecucion
FROM dbo.sysjobs j
LEFT JOIN dbo.sysjobactivity ja
       ON ja.job_id = j.job_id
      AND ja.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE j.name LIKE N'sm_backoffice - Resumen venta diaria%';
GO
