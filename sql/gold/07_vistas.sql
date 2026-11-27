-- =====================================================================
-- 07_vistas.sql — Vistas del modelo (esquema dw)
-- v_conciliacion_pedidos (R12, D23, D27): por pedido, lo vendido
-- (precio + flete de fact_ventas) contra lo pagado (fact_pedidos).
-- Ningún monto se guarda dos veces: la vista lo calcula al consultarla.
-- D35: hasta 0.05 de menos es redondeo de cuotas, no alerta.
-- En el Editor de consultas: ejecutar el CREATE OR ALTER VIEW solo.
-- =====================================================================

CREATE OR ALTER VIEW dw.v_conciliacion_pedidos
AS
WITH vendido AS (
    SELECT order_id,
           SUM(precio + flete) AS monto_vendido
    FROM dw.fact_ventas
    GROUP BY order_id
)
SELECT
    p.order_id,
    p.sk_fecha_compra,
    p.sk_cliente,
    p.sk_estado_pedido,
    p.tiene_items,
    p.tiene_pago,
    COALESCE(v.monto_vendido, 0)                  AS monto_vendido,
    p.monto_pagado,
    p.monto_pagado - COALESCE(v.monto_vendido, 0) AS diferencia,
    CASE
        WHEN p.tiene_items = 0 AND p.tiene_pago = 0 THEN 'sin_items_sin_pago'
        WHEN p.tiene_items = 0                      THEN 'pago_sin_items'
        WHEN p.tiene_pago  = 0                      THEN 'items_sin_pago'
        WHEN p.monto_pagado = v.monto_vendido       THEN 'cuadra'
        WHEN p.monto_pagado > v.monto_vendido       THEN 'pagado_mayor'
        WHEN p.monto_pagado >= v.monto_vendido - 0.05 THEN 'redondeo'      -- D35
        ELSE                                             'pagado_menor'
    END AS resultado,
    CAST(CASE WHEN p.tiene_items = 1
               AND (p.tiene_pago = 0 OR p.monto_pagado < v.monto_vendido - 0.05)
              THEN 1 ELSE 0 END AS BIT) AS alerta
FROM dw.fact_pedidos p
LEFT JOIN vendido v
       ON v.order_id = p.order_id;
GO
