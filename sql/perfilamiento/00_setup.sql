-- =====================================================================
-- 00_setup.sql — Preparación del perfilamiento
-- Motor: Azure Synapse SQL serverless (pool "Integrado" / Built-in)
-- Área de trabajo: syn-olist-fabri01 (Canada Central, ver D20)
-- Los datos NO se cargan: se leen directo desde el data lake (bronze).
-- Ejecutar cada sentencia por separado (CREATE VIEW debe ir sola).
-- =====================================================================

-- 1) Base de datos solo para perfilar (no guarda datos, solo vistas).
--    Intercalación UTF-8: los CSV están en portugués (ã, ç, é).
--    BIN2: comparación binaria (distingue mayúsculas y tildes) y más rápida.
--    Ejecutar en master.
CREATE DATABASE olist_perfilamiento
COLLATE Latin1_General_100_BIN2_UTF8;

-- (Cambiar a la base olist_perfilamiento antes de seguir)

-- 2) "Atajo" a la carpeta de bronce en el lake (puerta dfs = Data Lake Gen2).
CREATE EXTERNAL DATA SOURCE bronze_olist
WITH (LOCATION = 'https://stolistfabri01.dfs.core.windows.net/bronze/olist/');

-- 3) Una vista por cada CSV que entra al modelo (reviews y geolocation
--    quedan fuera, ver D17). La vista no copia datos: lee el CSV al consultarla.
--    NOTA: estas vistas dejan que OPENROWSET infiera los tipos. Sirven para
--    explorar, pero el perfilamiento demostró que la inferencia falla
--    (float en montos, ceros a la izquierda en códigos postales).
--    En plata los tipos se declaran siempre con WITH.

CREATE VIEW v_orders AS
SELECT * FROM OPENROWSET(BULK 'olist_orders_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_order_items AS
SELECT * FROM OPENROWSET(BULK 'olist_order_items_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_payments AS
SELECT * FROM OPENROWSET(BULK 'olist_order_payments_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_customers AS
SELECT * FROM OPENROWSET(BULK 'olist_customers_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_products AS
SELECT * FROM OPENROWSET(BULK 'olist_products_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_category_translation AS
SELECT * FROM OPENROWSET(BULK 'product_category_name_translation.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

CREATE VIEW v_sellers AS
SELECT * FROM OPENROWSET(BULK 'olist_sellers_dataset.csv', DATA_SOURCE = 'bronze_olist',
     FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS r;

-- Verificar los atajos creados:
SELECT name, location FROM sys.external_data_sources;
