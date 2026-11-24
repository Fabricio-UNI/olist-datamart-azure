-- =====================================================================
-- 07_customers.sql — Perfilamiento de olist_customers_dataset
-- Alimenta: dim_cliente (D5) y dim_ubicacion (D6)
-- =====================================================================

-- Revisión 1: duplicados y los dos identificadores
-- Resultado: 99,441 filas = 99,441 customer_id (= pedidos de orders: 1 por pedido)
--            96,096 personas distintas (customer_unique_id)
--   -> 3,345 compras hechas por personas que ya habían comprado. Valida D5.
SELECT
  COUNT(*)                           AS filas,
  COUNT(DISTINCT customer_id)        AS customer_ids_distintos,
  COUNT(DISTINCT customer_unique_id) AS personas_distintas
FROM v_customers;

-- Revisión 1b: clientes recurrentes (personas con más de un pedido)
-- Resultado: 2,997 personas (3.1% de 96,096) | máximo 17 pedidos de una persona
SELECT COUNT(*) AS clientes_recurrentes, MAX(pedidos) AS max_pedidos_de_una_persona
FROM (
  SELECT customer_unique_id, COUNT(*) AS pedidos
  FROM v_customers
  GROUP BY customer_unique_id
  HAVING COUNT(*) > 1
) AS recurrentes;

-- Revisión 2: nulos (el código postal sin NULLIF: se infiere como número)
-- Resultado: 0 | 0 | 0 | 0
SELECT
  SUM(CASE WHEN NULLIF(customer_unique_id, '') IS NULL THEN 1 ELSE 0 END) AS sin_persona,
  SUM(CASE WHEN customer_zip_code_prefix        IS NULL THEN 1 ELSE 0 END) AS sin_codigo_postal,
  SUM(CASE WHEN NULLIF(customer_city, '')       IS NULL THEN 1 ELSE 0 END) AS sin_ciudad,
  SUM(CASE WHEN NULLIF(customer_state, '')      IS NULL THEN 1 ELSE 0 END) AS sin_estado
FROM v_customers;

-- Revisión 3a: estados y códigos postales que perdieron el 0
-- Resultado: 27 estados | 23,995 códigos con menos de 5 dígitos (24%)
SELECT
  COUNT(DISTINCT customer_state) AS estados_distintos,
  SUM(CASE WHEN LEN(CAST(customer_zip_code_prefix AS VARCHAR(10))) < 5
           THEN 1 ELSE 0 END)    AS codigos_con_menos_de_5_digitos
FROM v_customers;

-- Revisión 3b: personas que compraron desde más de una ciudad (valida D6)
-- Resultado: 122
SELECT COUNT(*) AS personas_con_mas_de_una_ciudad
FROM (
  SELECT customer_unique_id
  FROM v_customers
  GROUP BY customer_unique_id
  HAVING COUNT(DISTINCT customer_city) > 1
) AS t;

-- Revisión 3c: variantes de São Paulo (comparar con sellers)
-- Resultado: sao paulo 15,540 (una sola forma) | sao paulo do potengi 2
--            sao paulo das missoes 2 | morro de sao paulo 1 (otras ciudades reales)
SELECT customer_city, COUNT(*) AS pedidos
FROM v_customers
WHERE LOWER(customer_city) LIKE '%sao paulo%'
   OR LOWER(customer_city) LIKE '%são paulo%'
GROUP BY customer_city
ORDER BY pedidos DESC;

-- Revisión 4: integridad en los dos sentidos
-- Resultado: 0 pedidos sin cliente | 0 clientes sin pedido -> relación 1 a 1
SELECT
  (SELECT COUNT(*) FROM v_orders o
     LEFT JOIN v_customers c ON o.customer_id = c.customer_id
     WHERE c.customer_id IS NULL) AS pedidos_sin_cliente,
  (SELECT COUNT(*) FROM v_customers c
     LEFT JOIN v_orders o ON c.customer_id = o.customer_id
     WHERE o.customer_id IS NULL) AS clientes_sin_pedido;
