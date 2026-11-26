-- ════════════════════════════════════════════════════════════════════════════════════
-- ███ SE CORRE EN AZURE, base sm_seguridad de PRODUCCIÓN ███  — SOLO LECTURA, no modifica nada
-- Inventario previo a la migración de seguridad de smb_react
-- ════════════════════════════════════════════════════════════════════════════════════
-- Muestra qué roles, privilegios y usuarios de las pantallas de smb_react se van a migrar,
-- para decidir antes de correr 02 a 06. No abre transacción.

USE sm_seguridad;
GO

DECLARE @paths TABLE (path NVARCHAR(200) PRIMARY KEY);
INSERT INTO @paths VALUES
 (N'/plan-hornos/aph'),(N'/plan-hornos/pedido-cocina'),(N'/plan-hornos/proceso-hornos'),
 (N'/plan-hornos/auxiliar'),(N'/plan-hornos/formato-rotacion'),(N'/plan-hornos/devolucion'),
 (N'/plan-hornos/motor-calculo'),(N'/plan-hornos/control'),(N'/plan-hornos/parametrizacion'),
 (N'/reportes'),(N'/gestion-placas'),(N'/ventas/resumen'),(N'/ventas/ranking'),
 (N'/presupuesto/gastos'),(N'/admin/seguridad');

-- 1. Pantallas de smb_react que NO existen en sct de prod (deben salir vacías o ser las esperadas)
SELECT '1. Pantalla no existe en prod' AS consulta, p.path
FROM @paths p
WHERE NOT EXISTS (SELECT 1 FROM sct.seg_mod_modulo m WHERE m.mod_path = p.path);

-- 2. Roles con pantallas de smb_react, por negocio
SELECT '2. Roles por negocio' AS consulta, r.rol_codigo_neg, r.rol_codigo, r.rol_nombre, r.rol_estado,
       STRING_AGG(m.mod_path, ', ') WITHIN GROUP (ORDER BY m.mod_path) AS pantallas
FROM sct.seg_rol r
JOIN sct.seg_rmo_rol_modulo rmo ON rmo.rmo_codigo_neg = r.rol_codigo_neg AND rmo.rmo_codigo_rol = r.rol_codigo AND rmo.rmo_estado = 1
JOIN sct.seg_mod_modulo m       ON m.mod_codigo = rmo.rmo_codigo_mod
JOIN @paths p                   ON p.path = m.mod_path
GROUP BY r.rol_codigo_neg, r.rol_codigo, r.rol_nombre, r.rol_estado
ORDER BY r.rol_nombre, r.rol_codigo_neg;

-- 3. Roles que se UNIFICARÁN con permisos distintos según el negocio (revisar con el reporte A2 de la migración)
WITH por_negocio AS (
    SELECT LTRIM(RTRIM(r.rol_nombre)) AS nombre, r.rol_codigo_neg AS neg,
           STRING_AGG(m.mod_path, ', ') WITHIN GROUP (ORDER BY m.mod_path) AS pantallas
    FROM sct.seg_rol r
    JOIN sct.seg_rmo_rol_modulo rmo ON rmo.rmo_codigo_neg = r.rol_codigo_neg AND rmo.rmo_codigo_rol = r.rol_codigo AND rmo.rmo_estado = 1
    JOIN sct.seg_mod_modulo m       ON m.mod_codigo = rmo.rmo_codigo_mod
    JOIN @paths p                   ON p.path = m.mod_path
    WHERE r.rol_estado = 1
    GROUP BY LTRIM(RTRIM(r.rol_nombre)), r.rol_codigo_neg
)
SELECT '3. Se unifica con diferencias' AS consulta, nombre, neg, pantallas
FROM por_negocio
WHERE nombre IN (SELECT nombre FROM por_negocio GROUP BY nombre HAVING COUNT(DISTINCT pantallas) > 1)
ORDER BY nombre, neg;

-- 4. Privilegios definidos para pantallas de smb_react
SELECT '4. Privilegios' AS consulta, pri.pri_codigo_neg, m.mod_path, pri.pri_codigo, pri.pri_nombre
FROM sct.seg_pri_privilegios pri
JOIN sct.seg_mod_modulo m ON m.mod_codigo = pri.pri_codigo_mod
JOIN @paths p             ON p.path = m.mod_path
ORDER BY m.mod_path, pri.pri_codigo, pri.pri_codigo_neg;

-- 5. Privilegios asignados por rol y negocio
SELECT '5. Privilegios por rol' AS consulta, rpr.rpr_codigo_neg, r.rol_nombre, m.mod_path, rpr.rpr_codigo_pri, pri.pri_nombre
FROM sct.SEG_RPR_ROL_PRIVILEGIO rpr
JOIN sct.seg_rol r        ON r.rol_codigo_neg = rpr.rpr_codigo_neg AND r.rol_codigo = rpr.rpr_codigo_rol
JOIN sct.seg_mod_modulo m ON m.mod_codigo = rpr.rpr_codigo_mod
JOIN @paths p             ON p.path = m.mod_path
LEFT JOIN sct.seg_pri_privilegios pri
       ON pri.pri_codigo_neg = rpr.rpr_codigo_neg AND pri.pri_codigo_mod = rpr.rpr_codigo_mod AND pri.pri_codigo = rpr.rpr_codigo_pri
WHERE rpr.rpr_estado IS NULL OR rpr.rpr_estado = 1
ORDER BY r.rol_nombre, rpr.rpr_codigo_neg, m.mod_path, rpr.rpr_codigo_pri;

-- 6. Usuarios y asignaciones que se migrarán
SELECT '6. Totales' AS consulta, COUNT(DISTINCT uro.uro_codigo_usu) AS usuarios, COUNT(*) AS asignaciones
FROM sct.seg_uro_usuario_rol uro
WHERE uro.uro_estado = 1
  AND EXISTS (SELECT 1 FROM sct.seg_rmo_rol_modulo rmo
              JOIN sct.seg_mod_modulo m ON m.mod_codigo = rmo.rmo_codigo_mod
              JOIN @paths p ON p.path = m.mod_path
              WHERE rmo.rmo_codigo_neg = uro.uro_codigo_neg AND rmo.rmo_codigo_rol = uro.uro_codigo_rol AND rmo.rmo_estado = 1);

-- 7. Quién administra Seguridad hoy (debe seguir pudiendo después de la migración)
SELECT '7. Entra a Seguridad' AS consulta, uro.uro_codigo_neg, uro.uro_codigo_usu, r.rol_nombre
FROM sct.seg_uro_usuario_rol uro
JOIN sct.seg_rol r              ON r.rol_codigo_neg = uro.uro_codigo_neg AND r.rol_codigo = uro.uro_codigo_rol AND r.rol_estado = 1
JOIN sct.seg_rmo_rol_modulo rmo ON rmo.rmo_codigo_neg = uro.uro_codigo_neg AND rmo.rmo_codigo_rol = uro.uro_codigo_rol AND rmo.rmo_estado = 1
JOIN sct.seg_mod_modulo m       ON m.mod_codigo = rmo.rmo_codigo_mod AND m.mod_path = N'/admin/seguridad'
WHERE uro.uro_estado = 1
ORDER BY uro.uro_codigo_usu, uro.uro_codigo_neg;

-- 8. Nombre del rol de Sistemas en prod (para @roles del script 06)
SELECT DISTINCT '8. Roles tipo Sistemas' AS consulta, rol_nombre
FROM sct.seg_rol
WHERE rol_estado = 1 AND (rol_nombre LIKE N'%Sistema%' OR rol_nombre LIKE N'%CDI%')
ORDER BY rol_nombre;

-- 9. ¿Ya existe el esquema seg? (debe salir vacío en la primera corrida)
SELECT '9. Esquema seg existente' AS consulta, t.name AS tabla
FROM sys.tables t
WHERE t.schema_id = SCHEMA_ID(N'seg');
