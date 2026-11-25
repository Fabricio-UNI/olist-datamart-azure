-- =====================================================================
-- 03_verificar_payments.sql — Verificación de silver/olist/payments/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data source silver_olist)
-- Escrito por: df_silver_payments. Grano de fact_pagos: 1 fila = 1 pago.
-- Esperados: docs/perfilamiento.md (H-PA1 a H-PA8).
-- Ejecutar cada bloque por separado.
-- =====================================================================

-- 1) Tipos: payment_value decimal(10,2); cuotas y secuencia int
SELECT column_ordinal, name, system_type_name
FROM sys.dm_exec_describe_first_result_set(N'
SELECT * FROM OPENROWSET(BULK ''payments/*.parquet'', DATA_SOURCE = ''silver_olist'',
     FORMAT = ''PARQUET'') AS r', NULL, 0);

-- 2) Conteos, R11 y rangos
--    Resultado (25/11/2026, tras corregir la escala): 103,886 / 103,886 / 99,440 / 2 / 9 / 1 / 24. Coincide.
SELECT
    COUNT(*)                                                     AS pagos,            -- esperado 103,886 (H-PA1)
    COUNT(DISTINCT CONCAT(order_id, '-', payment_sequential))    AS llaves_unicas,    -- esperado 103,886
    COUNT(DISTINCT order_id)                                     AS pedidos,          -- esperado 99,440 (H-PA1)
    SUM(CASE WHEN payment_installments IS NULL THEN 1 ELSE 0 END) AS cuotas_null,     -- esperado 2 (R11, H-PA4)
    SUM(CASE WHEN payment_value = 0 THEN 1 ELSE 0 END)           AS pagos_en_cero,    -- esperado 9 (3 not_defined + 6 vouchers)
    MIN(payment_installments) AS cuotas_min,                                          -- esperado 1 (ya no hay 0)
    MAX(payment_installments) AS cuotas_max,                                          -- esperado 24 (H-PA7)
    MAX(payment_value)        AS monto_max                                            -- esperado 13,664.08 (H-PA7)
FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 3) Medios de pago: deben ser exactamente 5 (H-PA6) -> filas de dim_medio_pago
--    Resultado (25/11/2026, tras corregir la escala): credit_card 76,795 / 12,542,084.19 (73.9% / 78.3%) ·
--    boleto 19,784 / 2,869,361.27 · voucher 5,775 / 379,436.87 · debit_card 1,529 / 217,989.79 ·
--    not_defined 3 / 0.00. Coincide con H-PA6 y con el perfilamiento (voucher 5,775 / 379,436.87).
SELECT payment_type,
       COUNT(*)            AS pagos,
       SUM(payment_value)  AS monto,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1))                     AS pct_pagos,
       CAST(100.0 * SUM(payment_value) / SUM(SUM(payment_value)) OVER () AS DECIMAL(5,1)) AS pct_monto
FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
GROUP BY payment_type
ORDER BY pagos DESC;

-- 4) Integridad plata contra plata
--    a) pagos sin pedido (esperado 0, H-PA8)
SELECT COUNT(*) AS pagos_sin_pedido
FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p
LEFT JOIN OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
       ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

--    b) pedidos sin pago (esperado 1: bfbd0f9b..., H-PA2, D23) -> tiene_pago = 0 en fact_pedidos
--    Resultado (25/11/2026): 1 fila · bfbd0f9bdef84302105ad712db648a6c · delivered · 2016-09-15 12:16:38
SELECT o.order_id, o.order_status, o.order_purchase_timestamp
FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
LEFT JOIN OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p
       ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

-- 5) Adelanto de la conciliación R12 a nivel TOTAL:
--    lo pagado debe ser >= lo vendido (productos + flete), por los intereses de las cuotas.
SELECT
    (SELECT SUM(payment_value) FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS p)
        AS total_pagado,
    (SELECT SUM(price + freight_value) FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS i)
        AS total_vendido;   -- 13,591,643.70 + 2,251,909.54 = 15,843,553.24

-- 6) DIAGNÓSTICO: el bloque 2 dio 100 pagos en 0 y el perfilamiento dio 9.
--    Resultado 1.ª ejecución (25/11/2026): el CSV decía 0.49, 0.48, 0.34... y plata 0.
--    Máximo afectado = 0.49 -> ADF REDONDEÓ A ENTERO (payment_value quedó decimal(10,0)).
--    2.ª ejecución: solo quedan ceros reales (bronce 0 = plata 0.00).
--    Comparamos el TEXTO ORIGINAL del CSV (bronce) contra el valor en plata,
--    solo para los pagos que en plata quedaron en 0.
SELECT TOP 30
    s.order_id, s.payment_sequential, s.payment_type,
    b.payment_value_texto AS bronce_texto,
    s.payment_value       AS plata
FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS s
JOIN OPENROWSET(BULK 'olist_order_payments_dataset.csv', DATA_SOURCE = 'bronze_olist',
                FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE)
     WITH (order_id             VARCHAR(32) 1,   -- el número es la posición de la columna en el CSV
           payment_sequential   INT         2,
           payment_type         VARCHAR(20) 3,
           payment_installments INT         4,
           payment_value_texto  VARCHAR(30) 5) AS b
  ON s.order_id = b.order_id AND s.payment_sequential = b.payment_sequential
WHERE s.payment_value = 0
ORDER BY b.payment_value_texto DESC;

-- 7) DIAGNÓSTICO: ¿cuánto dinero se perdió? Bronce (texto -> decimal en SQL) contra plata
--    Resultado 1.ª ejecución (25/11/2026): bronce 16,008,872.12 vs plata 16,009,845 (sin centavos,
--    +972.88). Causa: escala 0 en la proyección. Corrección: decimal(10,2) y reejecutar.
--    Resultado 2.ª ejecución (25/11/2026): bronce = plata = 16,008,872.12. Corregido.
SELECT
    (SELECT SUM(CAST(payment_value_texto AS DECIMAL(12,2)))
       FROM OPENROWSET(BULK 'olist_order_payments_dataset.csv', DATA_SOURCE = 'bronze_olist',
                       FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE)
            WITH (order_id VARCHAR(32) 1, payment_sequential INT 2, payment_type VARCHAR(20) 3,
                  payment_installments INT 4, payment_value_texto VARCHAR(30) 5) AS b) AS total_bronce,
    (SELECT SUM(payment_value)
       FROM OPENROWSET(BULK 'payments/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS s) AS total_plata;
