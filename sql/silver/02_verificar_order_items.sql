-- =====================================================================
-- 02_verificar_order_items.sql — Verificación de silver/olist/order_items/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data source silver_olist,
-- creado en 01_verificar_orders.sql)
-- Escrito por: df_silver_order_items. Grano de fact_ventas: 1 fila = 1 ítem.
-- Esperados: docs/perfilamiento.md (H-I1 a H-I5).
-- Ejecutar cada bloque por separado.
-- =====================================================================

-- 1) Tipos: price y freight_value deben salir decimal(10,2), NO float
SELECT column_ordinal, name, system_type_name
FROM sys.dm_exec_describe_first_result_set(N'
SELECT * FROM OPENROWSET(BULK ''order_items/*.parquet'', DATA_SOURCE = ''silver_olist'',
     FORMAT = ''PARQUET'') AS r', NULL, 0);

-- 2) Conteos y grano
--    Resultado (24/11/2026): 112,650 / 112,650 / 98,666 pedidos / 383 / 0.85 / 6,735.00 / 0.00 / 409.68
--    Coincide con H-I1, H-I3, H-I4. HALLAZGO NUEVO: 99,441 - 98,666 = 775 pedidos SIN ítems (ver bloque 5).
SELECT
    COUNT(*)                                                  AS filas,          -- esperado 112,650 (H-I1)
    COUNT(DISTINCT CONCAT(order_id, '-', order_item_id))      AS llaves_unicas,  -- esperado 112,650 (sin duplicados)
    COUNT(DISTINCT order_id)                                  AS pedidos,
    SUM(CASE WHEN freight_value = 0 THEN 1 ELSE 0 END)        AS flete_cero,     -- esperado 383 (H-I3, R9: se conservan)
    MIN(price) AS precio_min, MAX(price) AS precio_max,                          -- esperado 0.85 / 6,735.00 (H-I4)
    MIN(freight_value) AS flete_min, MAX(freight_value) AS flete_max             -- esperado 0.00 / 409.68 (H-I4)
FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 3) La prueba del decimal: en bronce, con inferencia (FLOAT), la suma salió
--    13591643.70001419. En plata, con decimal(10,2), debe salir EXACTA.
--    Resultado (24/11/2026): 13591643.70 y 2251909.54 EXACTOS. Antes (FLOAT): 13591643.70001419.
SELECT
    SUM(price)         AS ventas_total,   -- esperado 13591643.70 (sin decimales fantasma)
    SUM(freight_value) AS flete_total
FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 4) Integridad plata contra plata: todo ítem debe tener su pedido en silver/orders
--    Resultado (24/11/2026): 0. Coincide con H-I5.
SELECT COUNT(*) AS items_sin_pedido   -- esperado 0 (H-I5)
FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS i
LEFT JOIN OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
       ON i.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 5) HALLAZGO NUEVO (H-O10): pedidos sin ningún ítem. ¿De qué estado son?
--    Impacto: no generan filas en fact_ventas (grano = ítem). Si tienen pago,
--    aparecerán en fact_pagos sin venta -> la conciliación R12 debe explicarlos.
--    Resultado (24/11/2026): unavailable 603 · canceled 164 · created 5 · invoiced 2 · shipped 1 = 775
SELECT o.order_status, COUNT(*) AS pedidos_sin_items
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
LEFT JOIN OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS i
       ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY pedidos_sin_items DESC;

-- 6) ¿Por qué fact_ventas es necesaria? (D27)
--    Si hay pedidos con varios productos o vendedores, no se puede asignar
--    UN producto/vendedor por pedido -> el grano de ventas tiene que ser el ítem.
--    Resultado (24/11/2026): 98,666 pedidos con ítems · 9,803 con varios ítems ·
--    3,236 con varios productos · 1,278 con varios vendedores (marketplace). Confirma D27.
SELECT
    COUNT(*)                                          AS pedidos_con_items,
    SUM(CASE WHEN n_items > 1      THEN 1 ELSE 0 END) AS con_varios_items,
    SUM(CASE WHEN n_productos > 1  THEN 1 ELSE 0 END) AS con_varios_productos,
    SUM(CASE WHEN n_vendedores > 1 THEN 1 ELSE 0 END) AS con_varios_vendedores
FROM (
    SELECT order_id,
           COUNT(*)                   AS n_items,
           COUNT(DISTINCT product_id) AS n_productos,
           COUNT(DISTINCT seller_id)  AS n_vendedores
    FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
    GROUP BY order_id
) t;
