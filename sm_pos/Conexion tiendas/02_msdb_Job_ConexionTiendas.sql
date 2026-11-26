-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base msdb (SQL Server Agent del servidor de sm_pos) ███
-- Conexión de tiendas · Paso 2 de 2: job cada 3 horas, todos los días.
-- Requiere el paso 1 ejecutado y dbo.usp_TLS_ValidarConexionTiendas probado a mano.
-- Idempotente: si el job ya existe, lo borra y lo vuelve a crear.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Corre a las 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00 y 21:00.
-- Independiente del job del Ranking (sm_backoffice - Ranking ventas (importacion)).
-- El job corre con el dueño del SQL Agent: necesita el linked server [10.138.58.142] y escribir en sm_pos.

USE msdb;
GO

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_pos - Validar conexion tiendas')
    EXEC dbo.sp_delete_job @job_name = N'sm_pos - Validar conexion tiendas', @delete_unused_schedule = 1;
GO

EXEC dbo.sp_add_job
    @job_name = N'sm_pos - Validar conexion tiendas',
    @description = N'Prueba la conexión Azure -> KIO -> tienda de las tiendas activas que importan venta y registra OK o ERROR con el motivo en sm_pos.dbo.TLS_LogConexionTienda.';

EXEC dbo.sp_add_jobstep
    @job_name = N'sm_pos - Validar conexion tiendas',
    @step_name = N'Validar conexion',
    @subsystem = N'TSQL',
    @database_name = N'sm_pos',
    @command = N'EXEC dbo.usp_TLS_ValidarConexionTiendas;';

EXEC dbo.sp_add_schedule
    @schedule_name = N'Validar conexion tiendas - cada 3 horas',
    @freq_type = 4,              -- diario
    @freq_interval = 1,
    @freq_subday_type = 8,       -- horas
    @freq_subday_interval = 3,
    @active_start_time = 0;      -- desde las 00:00

EXEC dbo.sp_attach_schedule
    @job_name = N'sm_pos - Validar conexion tiendas',
    @schedule_name = N'Validar conexion tiendas - cada 3 horas';

EXEC dbo.sp_add_jobserver
    @job_name = N'sm_pos - Validar conexion tiendas';
GO

-- ─── Verificación: habilitado y con próxima ejecución ───────────────────────────────
SELECT j.name AS job, j.enabled AS habilitado, ja.next_scheduled_run_date AS proxima_ejecucion
FROM dbo.sysjobs j
LEFT JOIN dbo.sysjobactivity ja
       ON ja.job_id = j.job_id
      AND ja.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE j.name = N'sm_pos - Validar conexion tiendas';
GO
