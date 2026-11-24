-- =====================================================================
-- 01_orders.sql — Perfilamiento de olist_orders_dataset
-- Alimenta: fact_ventas, fact_pagos (fechas, estado, cliente),
--           dim_estado_pedido, dim_fecha (rango)
-- =====================================================================

-- Revisión 1: duplicados por llave (order_id)
-- Resultado: filas = pedidos_distintos = 99,441 -> sin duplicados
SELECT COUNT(*)                 AS filas,
       COUNT(DISTINCT order_id) AS pedidos_distintos
FROM v_orders;

-- Revisión 2: nulos en las fechas
-- NULLIF(col, '') convierte texto vacío en NULL (solo en columnas de TEXTO)
-- Resultado: sin_aprobacion = 160 | sin_entrega_transportista = 1,783
--            sin_entrega_cliente = 2,965 | sin_fecha_estimada = 0
SELECT
  SUM(CASE WHEN NULLIF(order_approved_at, '')             IS NULL THEN 1 ELSE 0 END) AS sin_aprobacion,
  SUM(CASE WHEN NULLIF(order_delivered_carrier_date, '')  IS NULL THEN 1 ELSE 0 END) AS sin_entrega_transportista,
  SUM(CASE WHEN NULLIF(order_delivered_customer_date, '') IS NULL THEN 1 ELSE 0 END) AS sin_entrega_cliente,
  SUM(CASE WHEN NULLIF(order_estimated_delivery_date, '') IS NULL THEN 1 ELSE 0 END) AS sin_fecha_estimada
FROM v_orders;

-- Revisión 3a: distribución de estados (valida dim_estado_pedido)
-- Resultado: 8 estados, suman 99,441
--   delivered 96,478 | shipped 1,107 | canceled 625 | unavailable 609
--   invoiced 314 | processing 301 | created 5 | approved 2
SELECT order_status, COUNT(*) AS pedidos
FROM v_orders
GROUP BY order_status
ORDER BY pedidos DESC;

-- Revisión 3b: rango de fechas de compra (valida dim_fecha 2016-2018)
-- TRY_CAST devuelve NULL si no puede convertir (en vez de dar error)
-- Resultado: 2016-09-04 21:15:19 -> 2018-10-17 17:30:18 | fechas_invalidas = 0
SELECT MIN(TRY_CAST(order_purchase_timestamp AS DATETIME2)) AS primera_compra,
       MAX(TRY_CAST(order_purchase_timestamp AS DATETIME2)) AS ultima_compra,
       SUM(CASE WHEN TRY_CAST(order_purchase_timestamp AS DATETIME2) IS NULL THEN 1 ELSE 0 END) AS fechas_invalidas
FROM v_orders;

-- Revisión 3c: pedidos 'delivered' sin fecha de entrega (hallazgo 5)
-- Resultado: 8
SELECT COUNT(*) AS entregados_sin_fecha
FROM v_orders
WHERE order_status = 'delivered'
  AND NULLIF(order_delivered_customer_date, '') IS NULL;

-- Revisión 3d: pedidos NO entregados que sí tienen fecha de entrega
-- (hallazgo nuevo, encontrado cuadrando: 2,963 no entregados vs 2,965 - 8 sin fecha)
-- Resultado: canceled = 6
SELECT order_status, COUNT(*) AS pedidos
FROM v_orders
WHERE order_status <> 'delivered'
  AND NULLIF(order_delivered_customer_date, '') IS NOT NULL
GROUP BY order_status;

-- Revisión 3e: entregas anteriores a la compra (hallazgo 6)
-- Resultado: 0 -> sospecha descartada
SELECT COUNT(*) AS entrega_antes_de_compra
FROM v_orders
WHERE TRY_CAST(order_delivered_customer_date AS DATETIME2)
    < TRY_CAST(order_purchase_timestamp AS DATETIME2);

-- Revisión 4: integridad referencial orders -> customers
-- Se revisa en 07_customers.sql. Resultado: 0 pedidos sin cliente.
