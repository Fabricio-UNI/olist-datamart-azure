-- =====================================================================
-- 09_combinacion_pago.sql — Combinación de medios de pago por pedido
-- Pregunta de negocio Pagos 2: "¿qué combinaciones de pago son más comunes?"
-- 1 fila = 1 pedido con pago (99,440). Junta los medios DISTINTOS del pedido
-- en un texto ordenado ("Tarjeta de credito + Voucher"), así la misma
-- combinación siempre se escribe igual. Lleva las llaves del pedido para
-- relacionarse con dim_fecha, dim_cliente y dim_ubicacion en Power BI.
-- En el Editor de consultas: ejecutar el CREATE OR ALTER VIEW solo.
-- =====================================================================

CREATE OR ALTER VIEW dw.v_combinacion_pago
AS
WITH medios AS (
    SELECT DISTINCT f.order_id, m.nombre
    FROM dw.fact_pagos f
    JOIN dw.dim_medio_pago m
      ON m.sk_medio_pago = f.sk_medio_pago
),
combinaciones AS (
    SELECT order_id,
           STRING_AGG(nombre, ' + ') WITHIN GROUP (ORDER BY nombre) AS combinacion,
           COUNT(*)                                                  AS cant_medios
    FROM medios
    GROUP BY order_id
)
SELECT
    c.order_id,
    c.combinacion,
    c.cant_medios,
    CAST(CASE WHEN c.cant_medios > 1 THEN 1 ELSE 0 END AS BIT) AS es_combinado,
    p.sk_fecha_compra,
    p.sk_cliente,
    p.sk_ubicacion_cliente,
    p.monto_pagado
FROM combinaciones c
JOIN dw.fact_pedidos p
  ON p.order_id = c.order_id;
GO
