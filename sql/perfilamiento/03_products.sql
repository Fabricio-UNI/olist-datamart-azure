-- =====================================================================
-- 03_products.sql — Perfilamiento de olist_products_dataset
-- Alimenta: dim_producto
-- =====================================================================

-- Revisión 1: duplicados por llave (product_id)
-- Resultado: filas = productos_distintos -> sin duplicados
SELECT COUNT(*)                   AS filas,
       COUNT(DISTINCT product_id) AS productos_distintos
FROM v_products;

-- Revisión 2: nulos (NULLIF solo en la columna de texto)
-- Resultado: sin_categoria = 610 | sin_peso = 2 | sin_largo = 2 | sin_alto = 2
--            sin_ancho = 2 | sin_fotos = 610
SELECT
  SUM(CASE WHEN NULLIF(product_category_name, '') IS NULL THEN 1 ELSE 0 END) AS sin_categoria,
  SUM(CASE WHEN product_weight_g   IS NULL THEN 1 ELSE 0 END) AS sin_peso,
  SUM(CASE WHEN product_length_cm  IS NULL THEN 1 ELSE 0 END) AS sin_largo,
  SUM(CASE WHEN product_height_cm  IS NULL THEN 1 ELSE 0 END) AS sin_alto,
  SUM(CASE WHEN product_width_cm   IS NULL THEN 1 ELSE 0 END) AS sin_ancho,
  SUM(CASE WHEN product_photos_qty IS NULL THEN 1 ELSE 0 END) AS sin_fotos
FROM v_products;

-- Revisión 2b: ¿son los mismos productos? (los conteos coincidían)
-- Resultado: 610 | 2 -> sí: 610 productos con catálogo incompleto,
--            2 productos sin ningún dato físico
SELECT
  SUM(CASE WHEN NULLIF(product_category_name, '') IS NULL
            AND product_photos_qty IS NULL THEN 1 ELSE 0 END) AS sin_categoria_y_sin_fotos,
  SUM(CASE WHEN product_weight_g  IS NULL AND product_length_cm IS NULL
            AND product_height_cm IS NULL AND product_width_cm  IS NULL
           THEN 1 ELSE 0 END) AS sin_peso_ni_medidas
FROM v_products;

-- Revisión 2c: impacto en ventas de los productos sin categoría
-- Resultado: 1,603 ítems (1.42%) | 179,535.28 (1.32% del monto total)
SELECT COUNT(*) AS items_vendidos_sin_categoria,
       SUM(i.price) AS monto_vendido_sin_categoria
FROM v_order_items i
JOIN v_products p ON i.product_id = p.product_id
WHERE NULLIF(p.product_category_name, '') IS NULL;

-- Revisión 3: valores raros en peso y medidas
-- Resultado: peso 0 a 40,425 g | largo 7 a 105 cm | peso_cero = 4 | medida_cero = 0
-- (7-105 cm sugiere medidas de paquete de envío, no del producto)
SELECT
  MIN(product_weight_g)  AS peso_min,  MAX(product_weight_g)  AS peso_max,
  MIN(product_length_cm) AS largo_min, MAX(product_length_cm) AS largo_max,
  SUM(CASE WHEN product_weight_g = 0 THEN 1 ELSE 0 END) AS peso_cero,
  SUM(CASE WHEN product_length_cm = 0 OR product_height_cm = 0
             OR product_width_cm = 0 THEN 1 ELSE 0 END) AS alguna_medida_cero
FROM v_products;

-- Revisión 4: integridad products -> category_translation (hallazgo 10)
-- Excluye los 610 sin categoría (no tienen nada que buscar)
-- Resultado: portateis_cozinha_e_preparadores_de_alimentos = 10 | pc_gamer = 3
--            -> se corrigen con referencia/correccion_traduccion_categorias.csv (D21)
SELECT p.product_category_name, COUNT(*) AS productos
FROM v_products p
LEFT JOIN v_category_translation t
  ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL
  AND NULLIF(p.product_category_name, '') IS NOT NULL
GROUP BY p.product_category_name;
