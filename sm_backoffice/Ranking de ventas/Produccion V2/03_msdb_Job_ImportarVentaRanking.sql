-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base msdb (SQL Server Agent del servidor de sm_backoffice) ███
-- PRODUCCIÓN V2 · Paso 3 de 4 · ÚNICO job del Ranking de Ventas.
-- Requiere el paso 2 ejecutado y vta.rvd_ImportarVentaRanking probado a mano (sección 7.1).
-- Idempotente: si el job ya existe, lo borra y lo vuelve a crear.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Cada 15 minutos (:00, :15, :30, :45): trae la venta de hoy de GT/SV (KIO) y USA (RankingGNDSALE)
-- y graba un bloque por tienda en vta.rvt_rvd_resumen_venta_diaria.
-- Entre 00:00 y 03:59 también el día anterior (ventas cerradas después de medianoche).
-- Al final, reintenta los días anteriores cuya última lectura falló (script 06).
-- El intervalo de 15 min está también en vta.rvd_IntervaloBloque: si se cambia aquí, cambiarlo allá.
-- Una corrida tarda ~5 min (29/10/2026: 85 tiendas KIO, 283 s). Si aún no termina cuando toca la
-- siguiente, SQL Agent se salta ese turno: ese bloque no existe y el siguiente lleva el acumulado.
-- El job corre con el dueño del SQL Agent: necesita el linked server [10.138.58.142], leer
-- sm_pos.dbo.RankingGNDSALE y escribir en sm_backoffice (normalmente ya es sysadmin).

USE msdb;
GO

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Ranking ventas (importacion)')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Ranking ventas (importacion)', @delete_unused_schedule = 1;
GO

EXEC dbo.sp_add_job
    @job_name = N'sm_backoffice - Ranking ventas (importacion)',
    @description = N'Ranking de Ventas: trae la venta de GT/SV (KIO) y USA (RankingGNDSALE) y graba un bloque por tienda en vta.rvt_rvd_resumen_venta_diaria.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_backoffice - Ranking ventas (importacion)',
    @step_name = N'Importar venta',
    @subsystem = N'TSQL',
    @database_name = N'sm_backoffice',
    @command = N'IF DATEPART(HOUR, GETDATE()) < 4
BEGIN
    DECLARE @ayer CHAR(8) = CONVERT(CHAR(8), DATEADD(DAY, -1, GETDATE()), 112);
    EXEC vta.rvd_ImportarVentaRanking @fecha = @ayer;
END;
EXEC vta.rvd_ImportarVentaRanking;
EXEC vta.rvd_ReintentarDiasPendientes;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Ranking ventas (importacion) - cada 15 minutos',
    @freq_type = 4,              -- diario
    @freq_interval = 1,
    @freq_subday_type = 4,       -- minutos
    @freq_subday_interval = 15,
    @active_start_time = 0;

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_backoffice - Ranking ventas (importacion)',
    @schedule_name = N'Ranking ventas (importacion) - cada 15 minutos';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_backoffice - Ranking ventas (importacion)';
GO

-- ─── Verificación: el único job del ranking, habilitado y con próxima ejecución ─────
SELECT j.name AS job, j.enabled AS habilitado, ja.next_scheduled_run_date AS proxima_ejecucion
FROM dbo.sysjobs j
LEFT JOIN dbo.sysjobactivity ja
       ON ja.job_id = j.job_id
      AND ja.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE j.name LIKE N'sm_backoffice - Ranking ventas%'
   OR j.name LIKE N'sm_backoffice - Resumen venta diaria%';
GO
