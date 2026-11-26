-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base msdb (SQL Server Agent del servidor de sm_backoffice) ███
-- PRODUCCIÓN V2 · Paso 1 de 4 · Borra los jobs del ranking de la versión anterior.
-- Correr ANTES del paso 2: así ningún job viejo escribe en el resumen mientras se le agregan los
-- bloques. Desde aquí y hasta correr el paso 3 el ranking no se actualiza (unos minutos).
-- Idempotente: si un job ya no existe, lo salta.
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- Se borran:
--   * Resumen venta diaria (incremental)     → USA pasa al job único (paso 3).
--   * Resumen venta diaria (recalculo 7 dias) → ya no aplica: cada corrida rehace el día completo.
--   * Ranking ventas GT/SV desde KIO          → lo reemplaza el job único (paso 3).

USE msdb;
GO

-- Si alguno está corriendo, esperar a que termine antes de ejecutar (sp_delete_job lo detiene).
SELECT j.name AS job, ja.start_execution_date AS corriendo_desde
FROM dbo.sysjobs j
JOIN dbo.sysjobactivity ja
  ON ja.job_id = j.job_id
 AND ja.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
  AND j.name IN (N'sm_backoffice - Resumen venta diaria (incremental)',
                 N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)',
                 N'sm_backoffice - Ranking ventas GT/SV desde KIO');
GO

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Resumen venta diaria (incremental)')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Resumen venta diaria (incremental)', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Resumen venta diaria (recalculo 7 dias)', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sm_backoffice - Ranking ventas GT/SV desde KIO')
    EXEC dbo.sp_delete_job @job_name = N'sm_backoffice - Ranking ventas GT/SV desde KIO', @delete_unused_schedule = 1;
GO

-- Verificación: no debe devolver filas.
SELECT name FROM dbo.sysjobs
WHERE name LIKE N'sm_backoffice - Resumen venta diaria%'
   OR name = N'sm_backoffice - Ranking ventas GT/SV desde KIO';
GO
