-- =====================================================================
-- 04_verificar_category_translation.sql — Verificación de silver/olist/category_translation/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data sources silver_olist y bronze_olist)
-- Escrito por: df_silver_category_translation = traducción de Olist (71) UNION tabla de
-- corrección (8, D21 + D28), deduplicado por categoría con prioridad para la corrección.
-- Ejecutar cada bloque por separado.
-- =====================================================================

-- 1) Conteos y origen
--    Resultado (25/11/2026): 73 / 73 / 65 olist / 8 correccion. Coincide.
SELECT
    COUNT(*)                                                    AS categorias,          -- esperado 73 (71 + 2 nuevas)
    COUNT(DISTINCT product_category_name)                       AS categorias_unicas,   -- esperado 73
    SUM(CASE WHEN origen = 'olist'      THEN 1 ELSE 0 END)      AS desde_olist,         -- esperado 65 (71 - 6 corregidas)
    SUM(CASE WHEN origen = 'correccion' THEN 1 ELSE 0 END)      AS desde_correccion     -- esperado 8 (2 D21 + 6 D28)
FROM OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 2) Las 8 correcciones: deben mostrar la traducción corregida
--    Resultado (25/11/2026): las 8 con su traducción corregida, motivo y fecha (2 del 23/11, 6 del 25/11).
SELECT product_category_name, product_category_name_english, motivo, fecha_correccion
FROM OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
WHERE origen = 'correccion'
ORDER BY fecha_correccion, product_category_name;

-- 3) Ninguno de los errores de Olist debe sobrevivir en plata (esperado 0 filas)
--    Resultado (25/11/2026): 0 filas. La prioridad de la corrección funciona.
SELECT product_category_name, product_category_name_english
FROM OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
WHERE product_category_name_english IN ('costruction_tools_garden', 'costruction_tools_tools',
      'fashio_female_clothing', 'home_confort', 'arts_and_craftmanship', 'security_and_services');

-- 4) Cobertura: toda categoría usada en products (bronce) debe tener traducción en plata.
--    Esperado 0 filas (antes de D21 salían portateis_cozinha... y pc_gamer). Los productos
--    sin categoría (NULL, 610) no cuentan: van a 'sin_categoria' (D14).
--    Resultado (25/11/2026): 0 filas. D21 + D28 cubren todas las categorías usadas.
SELECT p.product_category_name, COUNT(*) AS productos
FROM OPENROWSET(BULK 'olist_products_dataset.csv', DATA_SOURCE = 'bronze_olist',
                FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE)
     WITH (product_id VARCHAR(32) 1, product_category_name VARCHAR(100) 2) AS p
LEFT JOIN OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS t
       ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND p.product_category_name <> ''
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name;
