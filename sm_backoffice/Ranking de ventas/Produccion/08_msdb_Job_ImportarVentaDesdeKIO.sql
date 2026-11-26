-- ════════════════════════════════════════════════════════════════════════════════════
-- ⚠ REEMPLAZADO POR "Produccion V2/03" (job único). NO volver a ejecutar.
-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base msdb (SQL Server Agent del servidor de sm_backoffice) ███
-- PRODUCCIÓN · Ranking desde KIO · Job. Requiere 06 (KIO) y 07 (Azure) ya ejecutados y el SP
-- vta.rvd_ImportarVentaDesdeKIO probado a mano.
-- Idempotente: si el job ya existe, lo borra y lo vuelve a crear.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Cada 15 minutos: importa el día de hoy de GT/SV desde KIO al resumen.
-- Entre 00:00 y 03:59 también el día anterior (ventas cerradas después de medianoche), siempre que
-- no sea anterior a la fecha de corte (vta.rvd_FechaCorteKIO).
-- Una corrida completa tarda ~5 min (29/10/2026: 85 tiendas, 283 s). Si una corrida aún no termina
-- cuando toca la siguiente, SQL Agent no la vuelve a lanzar: se salta ese turno.
-- El job corre con el dueño del SQL Agent: necesita usar el linked server [10.138.58.142] y
-- escribir en sm_backoffice (normalmente ya es sysadmin).

USE msdb;
GO

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Ranking ventas GT/SV desde KIO')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO', @delete_unused_schedule = 1;
GO

EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO',
    @description = N'Ranking de Ventas: trae la venta de GT/SV por KIO y la escribe en vta.rvt_rvd_resumen_venta_diaria.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO',
    @step_name = N'Importar desde KIO',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'IF DATEPART(HOUR, GETDATE()) < 4
BEGIN
    DECLARE @ayer CHAR(8) = CONVERT(CHAR(8), DATEADD(DAY, -1, GETDATE()), 112);
    IF CONVERT(DATE, @ayer, 112) >= (SELECT fecha_corte FROM vta.rvd_FechaCorteKIO())
        EXEC vta.rvd_ImportarVentaDesdeKIO @fecha = @ayer;
END;
EXEC vta.rvd_ImportarVentaDesdeKIO;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Ranking ventas KIO - cada 15 minutos',
    @freq_type = 4,              -- diario
    @freq_interval = 1,
    @freq_subday_type = 4,       -- minutos
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO',
    @schedule_name = N'Ranking ventas KIO - cada 15 minutos';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO';
GO

-- ─── Verificación: habilitado y con próxima ejecución ───────────────────────────────
SELECT j.name AS job, j.enabled AS habilitado, ja.next_scheduled_run_date AS proxima_ejecucion
FROM dbo.sysjobs j
LEFT JOIN dbo.sysjobactivity ja
       ON ja.job_id = j.job_id
      AND ja.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE j.name = N'sm_backoffice - Ranking ventas GT/SV desde KIO';
GO
