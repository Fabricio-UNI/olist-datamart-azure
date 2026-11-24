-- =====================================================================
-- 01_verificar_orders.sql — Verificación de silver/olist/orders/
-- Motor: Synapse SQL serverless (pool Integrado), base olist_perfilamiento
-- Escrito por: df_silver_orders (ADF), ejecutado desde pl_bronze_a_silver
-- Objetivo: comprobar que plata conserva EXACTAMENTE lo que vimos en el
-- perfilamiento (docs/perfilamiento.md, H-O1 a H-O7). Si algún número
-- cambia, el flujo perdió o alteró filas.
-- Ejecutar cada bloque por separado.
-- =====================================================================

-- 1) "Atajo" a la carpeta de plata (igual que bronze_olist en 00_setup.sql)
CREATE EXTERNAL DATA SOURCE silver_olist
WITH (LOCATION = 'https://stolistfabri01.dfs.core.windows.net/silver/olist/');

-- 2) Tipos: Parquet GUARDA el esquema. Ya no hace falta WITH (...):
--    las fechas deben salir como datetime2 y los IDs como varchar.
--    (En bronce, con CSV, la inferencia fallaba -> regla R1.)
--    Versión de función (dm_exec_...) para ver solo las columnas útiles.
--    Resultado (24/11/2026): IDs y estado = varchar(8000); 6 fechas = datetime2(7).
--    varchar(8000) porque Parquet no guarda longitud de texto: en oro el DDL
--    declara longitudes reales (ej. CHAR(32) para los hash de Olist).
SELECT column_ordinal, name, system_type_name, is_nullable
FROM sys.dm_exec_describe_first_result_set(N'
SELECT * FROM OPENROWSET(BULK ''orders/*.parquet'', DATA_SOURCE = ''silver_olist'',
     FORMAT = ''PARQUET'') AS r', NULL, 0);

-- 3) Conteos contra el perfilamiento
--    Resultado (24/11/2026): 99,441 / 99,441 / 160 / 1,783 / 2,965 /
--    2016-09-04 21:15:19 / 2018-10-17 17:30. Coincide 100% con H-O1, H-O2, H-O4, H-O5.
SELECT
    COUNT(*)                                                       AS filas,             -- esperado 99,441 (H-O1)
    COUNT(DISTINCT order_id)                                       AS pedidos_distintos, -- esperado 99,441 (dedup)
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END)             AS sin_aprobacion,    -- esperado 160   (H-O4)
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END)  AS sin_transportista, -- esperado 1,783 (H-O5)
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS sin_entrega,       -- esperado 2,965 (H-O5)
    MIN(order_purchase_timestamp)                                  AS primera_compra,    -- esperado 2016-09-04
    MAX(order_purchase_timestamp)                                  AS ultima_compra      -- esperado 2018-10-17
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 4) Estados: deben ser 8 y sumar 99,441 (H-O3)
--    Resultado (24/11/2026): delivered 96,478 · shipped 1,107 · canceled 625 ·
--    unavailable 609 · invoiced 314 · processing 301 · created 5 · approved 2 = 99,441
SELECT order_status, COUNT(*) AS pedidos
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
GROUP BY order_status
ORDER BY pedidos DESC;

-- 5) Las inconsistencias se CONSERVAN en plata (se tratan en oro, D24)
--    Resultado (24/11/2026): 8 y 6. Plata no las corrige, solo las conserva.
SELECT
    SUM(CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL     THEN 1 ELSE 0 END) AS delivered_sin_fecha, -- esperado 8 (H-O6)
    SUM(CASE WHEN order_status = 'canceled'  AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS canceled_con_fecha   -- esperado 6 (H-O7)
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 6) Linaje: todas las filas de una ejecución comparten fecha_carga
--    Resultado (24/11/2026): 1 fila, 2026-11-24 22:59:33 (UTC = 17:59 Lima), 99,441.
--    currentTimestamp() en ADF devuelve UTC: en oro/Power BI convertir si se muestra.
SELECT fecha_carga, COUNT(*) AS filas
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
GROUP BY fecha_carga;
