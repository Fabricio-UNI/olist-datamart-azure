-- =====================================================================
-- 05_sellers.sql — Perfilamiento de olist_sellers_dataset
-- Alimenta: dim_vendedor (D19) y dim_ubicacion (junto con customers)
-- No apunta a otra tabla: su integridad se revisó desde order_items.
-- =====================================================================

-- Revisiones 1 y 2: duplicados y nulos
-- Resultado: 3,095 filas = 3,095 vendedores distintos | 0 | 0 | 0
SELECT
  COUNT(*)                  AS filas,
  COUNT(DISTINCT seller_id) AS vendedores_distintos,
  SUM(CASE WHEN NULLIF(seller_zip_code_prefix, '') IS NULL THEN 1 ELSE 0 END) AS sin_codigo_postal,
  SUM(CASE WHEN NULLIF(seller_city, '')            IS NULL THEN 1 ELSE 0 END) AS sin_ciudad,
  SUM(CASE WHEN NULLIF(seller_state, '')           IS NULL THEN 1 ELSE 0 END) AS sin_estado
FROM v_sellers;

-- Revisión 3a: estados válidos
-- Resultado: 23 estados, todos 2 letras en mayúscula (faltan AL, AP, RR, TO)
--   SP 1,849 (60%) | PR 349 | MG 244 | SC 190 | RJ 171 | RS 129 | GO 40 | DF 30 ...
SELECT seller_state, COUNT(*) AS vendedores
FROM v_sellers
GROUP BY seller_state
ORDER BY vendedores DESC;

-- Revisión 3b: variantes de escritura de ciudades (hallazgo 12), ejemplo São Paulo
-- Resultado: São Paulo escrita de 7 formas (sao paulo, "sao paulo" con espacio,
--   sao paulo - sp, sao paulo sp, sao paulo / sao paulo, são paulo, sao paulop).
-- TRAMPAS: "carapicuiba / sao paulo", "jacarei / sao paulo", "maua/sao paulo",
--   "ribeirao preto / sao paulo", "santo andre/sao paulo" son OTRAS ciudades con
--   el ESTADO pegado; "paulo lopes" (SC) es un falso positivo del LIKE.
SELECT seller_city, COUNT(*) AS vendedores
FROM v_sellers
WHERE LOWER(seller_city) LIKE '%paulo%'
GROUP BY seller_city
ORDER BY vendedores DESC;

-- Revisión 3c: códigos postales con menos de 5 dígitos
-- Resultado: 1,027 (33%) -> OPENROWSET infirió la columna como NÚMERO y se
-- comió el 0 a la izquierda (01001 -> 1001). El CSV sí trae el cero.
SELECT
  SUM(CASE WHEN LEN(CAST(seller_zip_code_prefix AS VARCHAR(10))) < 5
           THEN 1 ELSE 0 END) AS codigos_con_menos_de_5_digitos
FROM v_sellers;

-- Verificación: leyendo con tipos declarados (WITH), el cero se conserva
-- Resultado: 04195, 01529, 09850... todos con LEN = 5
SELECT TOP 10 seller_zip_code_prefix,
       LEN(seller_zip_code_prefix) AS largo
FROM OPENROWSET(
    BULK 'olist_sellers_dataset.csv', DATA_SOURCE = 'bronze_olist',
    FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE
) WITH (
    seller_id              VARCHAR(32),
    seller_zip_code_prefix VARCHAR(5),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2)
) AS s
WHERE seller_zip_code_prefix LIKE '0%';
