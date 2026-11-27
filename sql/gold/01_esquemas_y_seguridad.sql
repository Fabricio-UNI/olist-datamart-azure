-- =====================================================================
-- 01_esquemas_y_seguridad.sql — Base olist_oro (Azure SQL, Canada Central)
-- Ejecutar conectado como administrador de Entra (tu cuenta), en el
-- Editor de consultas del portal. Se puede ejecutar completo de una vez.
-- Decisión D33: carga plata -> oro con staging + MERGE en procedimientos.
-- =====================================================================

-- 1) Esquemas: stg = copia de plata (se vacía y recarga); dw = modelo estrella
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dw')  IS NULL EXEC('CREATE SCHEMA dw');

-- 2) La identidad administrada de ADF como usuario de la base (sin contraseña).
--    FROM EXTERNAL PROVIDER = la identidad vive en Microsoft Entra, no en SQL.
IF USER_ID('adf-olist-fabri01') IS NULL
    CREATE USER [adf-olist-fabri01] FROM EXTERNAL PROVIDER;

-- 3) Mínimo privilegio para ADF:
--    stg: copiar datos (INSERT) y vaciar antes de cada carga (TRUNCATE requiere ALTER)
GRANT SELECT, INSERT, DELETE, ALTER ON SCHEMA::stg TO [adf-olist-fabri01];
--    dw: NO puede escribir directo en las tablas; solo ejecutar los procedimientos de carga.
--    Los procedimientos (dueño dbo) escriben en dw por encadenamiento de propiedad.
GRANT EXECUTE ON SCHEMA::dw TO [adf-olist-fabri01];

-- 4) Verificación
SELECT name AS esquema FROM sys.schemas WHERE name IN ('stg', 'dw');
SELECT pr.name AS usuario, pe.permission_name, s.name AS esquema
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
JOIN sys.schemas s ON pe.major_id = s.schema_id
WHERE pr.name = 'adf-olist-fabri01';
