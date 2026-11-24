-- =====================================================================
-- 06_payments.sql — Perfilamiento de olist_order_payments_dataset
-- Alimenta: fact_pagos (es su grano: 1 fila = 1 pago) y dim_medio_pago
-- =====================================================================

-- Revisión 1: duplicados por llave COMPUESTA (order_id + payment_sequential)
-- Resultado: 103,886 filas = 103,886 llaves | 99,440 pedidos con pago
--   -> sin duplicados; 4,446 pagos extra (pedidos con varios medios de pago)
--   -> 99,441 pedidos en orders vs 99,440 con pago: falta 1
SELECT COUNT(*) AS filas,
       COUNT(DISTINCT CONCAT(order_id, '-', payment_sequential)) AS llaves_distintas,
       COUNT(DISTINCT order_id) AS pedidos_con_pago
FROM v_payments;

-- Revisión 1b: el pedido sin ningún pago (orders a la izquierda: se audita orders)
-- Resultado: bfbd0f9bdef84302105ad712db648a6c | delivered | 2016-09-15 12:16:38
--   -> no se inventa un pago (opción A); aparece en la conciliación
SELECT o.order_id, o.order_status, o.order_purchase_timestamp
FROM v_orders o
LEFT JOIN v_payments p ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

-- Revisión 2: nulos (NULLIF solo en la columna de texto)
-- Resultado: 0 | 0 | 0
SELECT
  SUM(CASE WHEN NULLIF(payment_type, '') IS NULL THEN 1 ELSE 0 END) AS sin_medio_pago,
  SUM(CASE WHEN payment_installments     IS NULL THEN 1 ELSE 0 END) AS sin_cuotas,
  SUM(CASE WHEN payment_value            IS NULL THEN 1 ELSE 0 END) AS sin_monto
FROM v_payments;

-- Revisión 3a: medios de pago vs dim_medio_pago (5 valores escritos a mano)
-- Resultado: exactamente los 5 previstos
--   credit_card 76,795 pagos | 12,542,084.19
--   boleto      19,784       |  2,869,361.27
--   voucher      5,775       |    379,436.87
--   debit_card   1,529       |    217,989.79
--   not_defined      3       |          0.00
SELECT payment_type, COUNT(*) AS pagos, SUM(payment_value) AS monto
FROM v_payments
GROUP BY payment_type
ORDER BY pagos DESC;

-- Revisión 3b: rangos de cuotas y montos
-- Resultado: cuotas 0 a 24 | pagos con 0 cuotas = 2
--            monto 0 a 13,664.08 | pagos con monto <= 0 = 9 (ninguno negativo)
SELECT
  MIN(payment_installments) AS cuotas_min,
  MAX(payment_installments) AS cuotas_max,
  SUM(CASE WHEN payment_installments = 0 THEN 1 ELSE 0 END) AS pagos_con_0_cuotas,
  MIN(payment_value) AS monto_min,
  MAX(payment_value) AS monto_max,
  SUM(CASE WHEN payment_value <= 0 THEN 1 ELSE 0 END) AS pagos_monto_cero_o_negativo
FROM v_payments;

-- Revisión 3c: de qué medio son los casos raros
-- (el WHERE es solo de presentación: oculta los medios sin casos; los números no cambian)
-- Resultado: voucher -> 6 con monto 0 | credit_card -> 2 con 0 cuotas
--            not_defined -> 3 con monto 0
SELECT payment_type,
       SUM(CASE WHEN payment_value = 0        THEN 1 ELSE 0 END) AS pagos_monto_cero,
       SUM(CASE WHEN payment_installments = 0 THEN 1 ELSE 0 END) AS pagos_cero_cuotas
FROM v_payments
WHERE payment_value = 0 OR payment_installments = 0
GROUP BY payment_type;

-- Revisión 3d: estado de los pedidos con pago not_defined
-- Resultado: los 3 son 'canceled' (cancelados antes de pagar)
--   00b1cb0320190ca0daa2c88b35206009 | 4637ca194b6387e2d538dc89b124b0ee
--   c8c528189310eaa44a745b8d9d26908b
SELECT p.order_id, p.payment_value, o.order_status
FROM v_payments p
JOIN v_orders o ON p.order_id = o.order_id
WHERE p.payment_type = 'not_defined';

-- Revisión 4: integridad payments -> orders (payments a la izquierda: se audita payments)
-- Orden lógico: 1) FROM + LEFT JOIN arma la tabla (sin pareja -> NULL a la derecha)
--               2) WHERE filtra esa tabla ya unida  3) SELECT cuenta
-- Resultado: 0 pagos huérfanos
SELECT COUNT(*) AS pagos_sin_pedido
FROM v_payments p
LEFT JOIN v_orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL;
