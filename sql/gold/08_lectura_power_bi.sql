-- =====================================================================
-- 08_lectura_power_bi.sql — Acceso de solo lectura para Power BI
-- Mínimo privilegio: un rol que solo puede LEER el esquema dw (dimensiones,
-- hechos y vistas). No ve stg ni puede ejecutar procedimientos.
-- El usuario es una cuenta de Microsoft Entra dedicada (sin contraseña SQL).
-- Reemplazar <usuario@dominio> por el UPN real del usuario de Entra.
-- =====================================================================

IF DATABASE_PRINCIPAL_ID('rol_lector_bi') IS NULL
    CREATE ROLE rol_lector_bi;

GRANT SELECT ON SCHEMA::dw TO rol_lector_bi;

IF USER_ID('<usuario@dominio>') IS NULL
    CREATE USER [<usuario@dominio>] FROM EXTERNAL PROVIDER;

ALTER ROLE rol_lector_bi ADD MEMBER [<usuario@dominio>];

-- Verificación: permisos del rol y sus miembros
SELECT pr.name AS principal, pe.permission_name, s.name AS esquema
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
JOIN sys.schemas s ON pe.major_id = s.schema_id
WHERE pr.name = 'rol_lector_bi';

SELECT r.name AS rol, m.name AS miembro
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE r.name = 'rol_lector_bi';
