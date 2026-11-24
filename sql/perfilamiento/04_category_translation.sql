-- =====================================================================
-- 04_category_translation.sql — Perfilamiento de product_category_name_translation
-- Alimenta: dim_producto (categoria_en)
-- No apunta a otra tabla: no tiene revisión de integridad propia.
-- Son textos: no hay valores numéricos raros que medir.
-- =====================================================================

-- Revisiones 1 y 2: duplicados y traducciones vacías
-- Una categoría repetida (con dos traducciones) duplicaría productos al unir.
-- Resultado: filas = categorias_distintas | sin_traduccion_en_ingles = 0
SELECT
  COUNT(*)                              AS filas,
  COUNT(DISTINCT product_category_name) AS categorias_distintas,
  SUM(CASE WHEN NULLIF(product_category_name_english, '') IS NULL
           THEN 1 ELSE 0 END)           AS sin_traduccion_en_ingles
FROM v_category_translation;
