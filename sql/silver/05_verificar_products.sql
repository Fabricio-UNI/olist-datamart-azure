-- =====================================================================
-- 05_verificar_products.sql — Verificación de silver/olist/products/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data source silver_olist)
-- Escrito por: df_silver_products. Base de dim_producto.
-- Reglas en plata: R6/D22 (peso y medidas en 0 -> NULL), vacío -> NULL en categoría.
-- R8 (sin_categoria / sin_traduccion) se aplica en oro (D14).
-- Esperados: docs/perfilamiento.md (H-P1 a H-P5).
-- Ejecutar cada bloque por separado.
-- =====================================================================

-- 1) Tipos: las 7 columnas numéricas deben ser int
SELECT column_ordinal, name, system_type_name
FROM sys.dm_exec_describe_first_result_set(N'
SELECT * FROM OPENROWSET(BULK ''products/*.parquet'', DATA_SOURCE = ''silver_olist'',
     FORMAT = ''PARQUET'') AS r', NULL, 0);

-- 2) Conteos y nulos
--    Resultado (25/11/2026): 32,951 / 32,951 / 610 / 610 / 6 / 0 / 2. Coincide; R6 aplicada.
SELECT
    COUNT(*)                                                          AS productos,           -- esperado 32,951
    COUNT(DISTINCT product_id)                                        AS productos_unicos,    -- esperado 32,951 (H-P1)
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END)    AS sin_categoria,       -- esperado 610 (H-P2)
    SUM(CASE WHEN product_photos_qty    IS NULL THEN 1 ELSE 0 END)    AS sin_fotos,           -- esperado 610 (H-P2, los mismos)
    SUM(CASE WHEN product_weight_g      IS NULL THEN 1 ELSE 0 END)    AS peso_null,           -- esperado 6 = 2 sin medidas (H-P3) + 4 en 0 (H-P4, R6)
    SUM(CASE WHEN product_weight_g      = 0     THEN 1 ELSE 0 END)    AS peso_cero,           -- esperado 0 (R6 aplicada)
    SUM(CASE WHEN product_length_cm     IS NULL THEN 1 ELSE 0 END)    AS largo_null           -- esperado 2 (H-P3)
FROM OPENROWSET(BULK 'products/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 3) Rangos (ninguna medida debe ser 0 ni negativa)
SELECT
    MIN(product_weight_g)  AS peso_min,  MAX(product_weight_g)  AS peso_max,
    MIN(product_length_cm) AS largo_min, MAX(product_length_cm) AS largo_max,
    MIN(product_height_cm) AS alto_min,  MAX(product_height_cm) AS alto_max,
    MIN(product_width_cm)  AS ancho_min, MAX(product_width_cm)  AS ancho_max
FROM OPENROWSET(BULK 'products/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 4) Integridad plata contra plata
--    a) ítems vendidos cuyo producto no está en plata (esperado 0, H-I5)
--    Resultado (25/11/2026): 0.
SELECT COUNT(*) AS items_sin_producto
FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS i
LEFT JOIN OPENROWSET(BULK 'products/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p
       ON i.product_id = p.product_id
WHERE p.product_id IS NULL;

--    b) productos con categoría pero sin traducción en plata (esperado 0, D21 + D28)
SELECT p.product_category_name, COUNT(*) AS productos
FROM OPENROWSET(BULK 'products/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p
LEFT JOIN OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS t
       ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- 5) Adelanto de dim_producto: ¿cuántos productos tendrán cada etiqueta de R8?
--    Resultado (25/11/2026): con_traduccion 32,341 · sin_categoria 610 · sin_traduccion 0 (D21 + D28).
SELECT
    CASE WHEN p.product_category_name IS NULL       THEN 'sin_categoria'
         WHEN t.product_category_name_english IS NULL THEN 'sin_traduccion'
         ELSE 'con_traduccion' END AS estado_categoria,
    COUNT(*) AS productos
FROM OPENROWSET(BULK 'products/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p
LEFT JOIN OPENROWSET(BULK 'category_translation/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS t
       ON p.product_category_name = t.product_category_name
GROUP BY CASE WHEN p.product_category_name IS NULL       THEN 'sin_categoria'
              WHEN t.product_category_name_english IS NULL THEN 'sin_traduccion'
              ELSE 'con_traduccion' END;
