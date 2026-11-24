-- =====================================================================
-- 02_order_items.sql — Perfilamiento de olist_order_items_dataset
-- Alimenta: fact_ventas (es su grano: 1 fila = 1 ítem de un pedido)
-- =====================================================================

-- Revisión 1: duplicados por llave COMPUESTA (order_id + order_item_id)
-- order_id solo NO sirve: un pedido con 3 ítems tiene 3 filas legítimas.
-- CONCAT porque T-SQL no permite COUNT(DISTINCT col1, col2).
-- Resultado: filas = llaves_distintas = 112,650 -> sin duplicados
SELECT COUNT(*) AS filas,
       COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) AS llaves_distintas
FROM v_order_items;

-- Alternativa que lista los duplicados (resultado vacío = no hay duplicados)
SELECT order_id, order_item_id, COUNT(*) AS veces
FROM v_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Revisión 2: nulos
-- Resultado: todos 0 en la columna de texto.
-- OJO: la primera versión usó NULLIF(freight_value, '') y dio 383 "nulos".
-- Error: freight_value se infirió como NÚMERO, y '' convertido a número es 0,
-- así que NULLIF contó los fletes en 0 como nulos. NULLIF(…, '') solo en TEXTO.
SELECT
  SUM(CASE WHEN NULLIF(product_id, '')          IS NULL THEN 1 ELSE 0 END) AS sin_producto,
  SUM(CASE WHEN NULLIF(seller_id, '')           IS NULL THEN 1 ELSE 0 END) AS sin_vendedor,
  SUM(CASE WHEN price         IS NULL THEN 1 ELSE 0 END) AS sin_precio,
  SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS sin_flete,
  SUM(CASE WHEN NULLIF(shipping_limit_date, '') IS NULL THEN 1 ELSE 0 END) AS sin_fecha_limite
FROM v_order_items;

-- Verificación del caso anterior: nulos reales vs ceros
-- Resultado: flete_nulo = 0 | flete_cero = 383 (envío gratis, valor VÁLIDO)
SELECT
  SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS flete_nulo,
  SUM(CASE WHEN freight_value = 0    THEN 1 ELSE 0 END) AS flete_cero
FROM v_order_items;

-- Revisión 3: valores raros en montos
-- Resultado: precio 0.85 a 6,735 (promedio ~120.65) | flete 0 a 409.68
--            precio_negativo = 0 | flete_negativo = 0
-- El promedio sale con muchos decimales: price se infirió como FLOAT (impreciso
-- para dinero). En plata: DECIMAL(10,2).
SELECT
  MIN(price) AS precio_min, MAX(price) AS precio_max, AVG(price) AS precio_promedio,
  MIN(freight_value) AS flete_min, MAX(freight_value) AS flete_max,
  SUM(CASE WHEN price < 0         THEN 1 ELSE 0 END) AS precio_negativo,
  SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS flete_negativo
FROM v_order_items;

-- Total vendido (referencia para porcentajes)
-- Resultado: 112,650 ítems | 13,591,643.70 (FLOAT muestra 13591643.70001419)
SELECT COUNT(*) AS items_totales, SUM(price) AS monto_total
FROM v_order_items;

-- Revisión 4: integridad referencial (ítems huérfanos)
-- LEFT JOIN: order_items a la IZQUIERDA (lo que se audita, se conserva completo),
-- el catálogo a la derecha (donde se busca). Sin pareja -> NULL -> huérfano.
-- Con INNER JOIN los huérfanos desaparecerían sin avisar.
-- Resultado: 0 | 0 | 0 -> ninguna venta cae en "Desconocido" por el catálogo
SELECT
  (SELECT COUNT(*) FROM v_order_items i
     LEFT JOIN v_orders o   ON i.order_id   = o.order_id
     WHERE o.order_id IS NULL)   AS items_sin_pedido,
  (SELECT COUNT(*) FROM v_order_items i
     LEFT JOIN v_products p ON i.product_id = p.product_id
     WHERE p.product_id IS NULL) AS items_sin_producto,
  (SELECT COUNT(*) FROM v_order_items i
     LEFT JOIN v_sellers s  ON i.seller_id  = s.seller_id
     WHERE s.seller_id IS NULL)  AS items_sin_vendedor;
