-- Ejecutar en msdb (SQL Server Agent del mismo servidor de sm_backoffice).
-- Requiere haber ejecutado 001_Create_rvd_ResumenVentaDiaria.sql.
--
-- Job 1: incremental cada 15 minutos.
-- Job 2: red de seguridad diaria a las 02:00 — recalcula completos los últimos 7 días.

USE msdb;
GO

-- ─── Job 1: incremental ─────────────────────────────────────────────────────────────
EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @description = N'Ranking de Ventas: actualiza vta.rvd_resumen_venta_diaria con lo nuevo de sm_pos.dbo.FiscalInvoice.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @step_name = N'Actualizar incremental',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'EXEC vta.rvd_ActualizarResumenIncremental;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Cada 15 minutos',
    @freq_type = 4,              -- diario
    @freq_interval = 1,
    @freq_subday_type = 4,       -- minutos
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)',
    @schedule_name = N'Cada 15 minutos';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Resumen venta diaria (incremental)';
GO

-- ─── Job 2: recálculo diario de los últimos 7 días ──────────────────────────────────
EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @description = N'Ranking de Ventas: red de seguridad — recalcula completos los últimos 7 días del resumen.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @step_name = N'Recalcular ultimos 7 dias',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'DECLARE @fin DATE = CAST(GETDATE() AS DATE);
DECLARE @ini DATE = DATEADD(DAY, -7, @fin);
EXEC vta.rvd_RecalcularResumenRango @fecha_ini = @ini, @fecha_fin = @fin;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Diario 02:00',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 20000;  -- 02:00:00

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
    @schedule_name = N'Diario 02:00';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)';
GO
