-- =====================================================================
-- 06_procedimientos.sql — Carga stg.* -> dw.* (D33, opción A)
-- Un procedimiento por tabla + un maestro (dw.usp_cargar_oro) que los
-- llama en orden dentro de una transacción (todo o nada).
-- Orden obligatorio por las claves foráneas: dimensiones -> hechos.
-- Cada procedimiento devuelve cuántas filas insertó y actualizó.
-- En el Editor de consultas del portal: ejecutar cada CREATE OR ALTER
-- solo (sin el GO). En SSMS / Azure Data Studio el archivo corre entero.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) dim_producto — SCD1 por product_id (D14, D21, D28, R8)
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_dim_producto
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH origen AS (
        SELECT
            p.product_id,
            COALESCE(p.product_category_name, 'sin_categoria') AS categoria_pt,
            CASE WHEN p.product_category_name IS NULL THEN 'sin_categoria'
                 ELSE COALESCE(t.product_category_name_english, 'sin_traduccion')
            END                                              AS categoria_en,
            p.product_weight_g                               AS peso_g,
            p.product_length_cm                              AS largo_cm,
            p.product_height_cm                              AS alto_cm,
            p.product_width_cm                               AS ancho_cm,
            CAST(p.product_photos_qty AS SMALLINT)           AS cantidad_fotos
        FROM stg.products p
        LEFT JOIN stg.category_translation t
               ON t.product_category_name = p.product_category_name
    )
    MERGE dw.dim_producto AS d
    USING origen AS o
       ON d.product_id = o.product_id
    WHEN MATCHED AND EXISTS (
            SELECT o.categoria_pt, o.categoria_en, o.peso_g, o.largo_cm, o.alto_cm, o.ancho_cm, o.cantidad_fotos
            EXCEPT
            SELECT d.categoria_pt, d.categoria_en, d.peso_g, d.largo_cm, d.alto_cm, d.ancho_cm, d.cantidad_fotos
         ) THEN
        UPDATE SET categoria_pt   = o.categoria_pt,
                   categoria_en   = o.categoria_en,
                   peso_g         = o.peso_g,
                   largo_cm       = o.largo_cm,
                   alto_cm        = o.alto_cm,
                   ancho_cm       = o.ancho_cm,
                   cantidad_fotos = o.cantidad_fotos,
                   fecha_carga    = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (product_id, categoria_pt, categoria_en, peso_g, largo_cm, alto_cm, ancho_cm, cantidad_fotos)
        VALUES (o.product_id, o.categoria_pt, o.categoria_en, o.peso_g, o.largo_cm, o.alto_cm, o.ancho_cm, o.cantidad_fotos)
    OUTPUT $action INTO @acciones;

    SELECT 'dim_producto' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 2) dim_vendedor — SCD1 por seller_id (D19, D31, D32, H-S6)
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_dim_vendedor
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH origen AS (
        SELECT
            s.seller_id,
            COALESCE(s.municipio, 'sin_municipio')  AS municipio,
            s.cod_municipio_ibge,
            COALESCE(s.estado, 'XX')                AS estado,
            COALESCE(r.region, 'Desconocida')       AS region
        FROM stg.sellers s
        LEFT JOIN dw.ref_region_estado r
               ON r.estado = s.estado
    )
    MERGE dw.dim_vendedor AS d
    USING origen AS o
       ON d.seller_id = o.seller_id
    WHEN MATCHED AND EXISTS (
            SELECT o.municipio, o.cod_municipio_ibge, o.estado, o.region
            EXCEPT
            SELECT d.municipio, d.cod_municipio_ibge, d.estado, d.region
         ) THEN
        UPDATE SET municipio          = o.municipio,
                   cod_municipio_ibge = o.cod_municipio_ibge,
                   estado             = o.estado,
                   region             = o.region,
                   fecha_carga        = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (seller_id, municipio, cod_municipio_ibge, estado, region)
        VALUES (o.seller_id, o.municipio, o.cod_municipio_ibge, o.estado, o.region)
    OUTPUT $action INTO @acciones;

    SELECT 'dim_vendedor' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 3) dim_ubicacion — grano (CP, municipio, estado), de vendedores y clientes
--    (D6, D7, D31, D32). La llave de negocio son las 3 columnas.
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_dim_ubicacion
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH todas AS (
        SELECT seller_zip_code_prefix AS cp, municipio, cod_municipio_ibge, estado FROM stg.sellers
        UNION ALL
        SELECT customer_zip_code_prefix, municipio, cod_municipio_ibge, estado FROM stg.customers
    ),
    origen AS (
        SELECT
            t.cp                                       AS codigo_postal_prefijo,
            COALESCE(t.municipio, 'sin_municipio')     AS municipio,
            MAX(t.cod_municipio_ibge)                  AS cod_municipio_ibge,
            COALESCE(t.estado, 'XX')                   AS estado,
            COALESCE(MAX(r.region), 'Desconocida')     AS region
        FROM todas t
        LEFT JOIN dw.ref_region_estado r
               ON r.estado = t.estado
        GROUP BY t.cp, COALESCE(t.municipio, 'sin_municipio'), COALESCE(t.estado, 'XX')
    )
    MERGE dw.dim_ubicacion AS d
    USING origen AS o
       ON  d.codigo_postal_prefijo = o.codigo_postal_prefijo
       AND d.municipio             = o.municipio
       AND d.estado                = o.estado
    WHEN MATCHED AND EXISTS (
            SELECT o.cod_municipio_ibge, o.region
            EXCEPT
            SELECT d.cod_municipio_ibge, d.region
         ) THEN
        UPDATE SET cod_municipio_ibge = o.cod_municipio_ibge,
                   region             = o.region,
                   fecha_carga        = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (codigo_postal_prefijo, municipio, cod_municipio_ibge, estado, region)
        VALUES (o.codigo_postal_prefijo, o.municipio, o.cod_municipio_ibge, o.estado, o.region)
    OUTPUT $action INTO @acciones;

    SELECT 'dim_ubicacion' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 4) dim_cliente — 1 fila = 1 persona (customer_unique_id, D5)
--    num_pedidos / es_recurrente / fecha_primera_compra cuentan solo
--    pedidos con al menos un ítem (D25, opción B aprobada 26/11).
--    Las personas cuyo único pedido no tiene ítems quedan con 0 pedidos
--    y fecha NULL, pero siguen en la dimensión (fact_pedidos las usa).
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_dim_cliente
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH personas AS (
        SELECT DISTINCT customer_unique_id
        FROM stg.customers
    ),
    pedidos_con_venta AS (
        SELECT c.customer_unique_id, o.order_id, o.order_purchase_timestamp
        FROM stg.orders o
        JOIN stg.customers c
          ON c.customer_id = o.customer_id
        WHERE EXISTS (SELECT 1 FROM stg.order_items i WHERE i.order_id = o.order_id)
    ),
    resumen AS (
        SELECT customer_unique_id,
               MIN(CAST(order_purchase_timestamp AS DATE)) AS fecha_primera_compra,
               COUNT(DISTINCT order_id)                    AS num_pedidos
        FROM pedidos_con_venta
        GROUP BY customer_unique_id
    ),
    origen AS (
        SELECT p.customer_unique_id,
               r.fecha_primera_compra,
               COALESCE(r.num_pedidos, 0)                                AS num_pedidos,
               CAST(CASE WHEN r.num_pedidos > 1 THEN 1 ELSE 0 END AS BIT) AS es_recurrente
        FROM personas p
        LEFT JOIN resumen r
               ON r.customer_unique_id = p.customer_unique_id
    )
    MERGE dw.dim_cliente AS d
    USING origen AS o
       ON d.customer_unique_id = o.customer_unique_id
    WHEN MATCHED AND EXISTS (
            SELECT o.fecha_primera_compra, o.num_pedidos, o.es_recurrente
            EXCEPT
            SELECT d.fecha_primera_compra, d.num_pedidos, d.es_recurrente
         ) THEN
        UPDATE SET fecha_primera_compra = o.fecha_primera_compra,
                   num_pedidos          = o.num_pedidos,
                   es_recurrente        = o.es_recurrente,
                   fecha_carga          = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (customer_unique_id, fecha_primera_compra, num_pedidos, es_recurrente)
        VALUES (o.customer_unique_id, o.fecha_primera_compra, o.num_pedidos, o.es_recurrente)
    OUTPUT $action INTO @acciones;

    SELECT 'dim_cliente' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 5) fact_pedidos — 1 fila = 1 pedido (snapshot acumulativo, D26, D27)
--    Todos los pedidos (99,441): LEFT JOIN a ítems y pagos.
--    D24: si el pedido está cancelado (grupo Cancelado), la fecha de
--    entrega no se usa. Fechas nulas o fuera del calendario -> -1.
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_fact_pedidos
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH items AS (
        SELECT order_id, COUNT(*) AS cant_items
        FROM stg.order_items
        GROUP BY order_id
    ),
    pagos AS (
        SELECT order_id, SUM(payment_value) AS monto_pagado
        FROM stg.payments
        GROUP BY order_id
    ),
    pedidos AS (
        SELECT
            o.order_id,
            o.order_status,
            o.order_purchase_timestamp       AS f_compra,
            o.order_approved_at              AS f_aprobacion,
            o.order_delivered_carrier_date   AS f_despacho,
            CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN NULL
                 ELSE o.order_delivered_customer_date END AS f_entrega,
            o.order_estimated_delivery_date  AS f_estimada,
            c.customer_unique_id,
            c.customer_zip_code_prefix       AS cp,
            COALESCE(c.municipio, 'sin_municipio') AS municipio,
            c.estado,
            COALESCE(i.cant_items, 0)        AS cant_items,
            COALESCE(p.monto_pagado, 0)      AS monto_pagado,
            CASE WHEN p.order_id IS NULL THEN 0 ELSE 1 END AS tiene_pago
        FROM stg.orders o
        LEFT JOIN stg.customers c ON c.customer_id = o.customer_id
        LEFT JOIN items i         ON i.order_id    = o.order_id
        LEFT JOIN pagos p         ON p.order_id    = o.order_id
    ),
    origen AS (
        SELECT
            x.order_id,
            COALESCE(fc.sk_fecha, -1)  AS sk_fecha_compra,
            COALESCE(fa.sk_fecha, -1)  AS sk_fecha_aprobacion,
            COALESCE(fd.sk_fecha, -1)  AS sk_fecha_despacho,
            COALESCE(fe.sk_fecha, -1)  AS sk_fecha_entrega,
            COALESCE(fs.sk_fecha, -1)  AS sk_fecha_estimada,
            COALESCE(dc.sk_cliente, -1)       AS sk_cliente,
            COALESCE(du.sk_ubicacion, -1)     AS sk_ubicacion_cliente,
            COALESCE(de.sk_estado_pedido, -1) AS sk_estado_pedido,
            CAST(x.cant_items AS SMALLINT)                              AS cant_items,
            CAST(CASE WHEN x.cant_items > 0 THEN 1 ELSE 0 END AS BIT)   AS tiene_items,
            CAST(x.tiene_pago AS BIT)                                   AS tiene_pago,
            CAST(x.monto_pagado AS DECIMAL(12,2))                       AS monto_pagado,
            DATEDIFF(HOUR, x.f_compra,     x.f_aprobacion) AS horas_aprobacion,
            DATEDIFF(DAY,  x.f_aprobacion, x.f_despacho)   AS dias_despacho,
            DATEDIFF(DAY,  x.f_compra,     x.f_entrega)    AS dias_entrega,
            DATEDIFF(DAY,  x.f_estimada,   x.f_entrega)    AS dias_retraso,
            CAST(CASE WHEN x.f_entrega IS NULL OR x.f_estimada IS NULL THEN NULL
                      WHEN DATEDIFF(DAY, x.f_estimada, x.f_entrega) > 0 THEN 1
                      ELSE 0 END AS TINYINT)               AS entrega_tardia
        FROM pedidos x
        LEFT JOIN dw.dim_fecha fc ON fc.fecha = CAST(x.f_compra     AS DATE)
        LEFT JOIN dw.dim_fecha fa ON fa.fecha = CAST(x.f_aprobacion AS DATE)
        LEFT JOIN dw.dim_fecha fd ON fd.fecha = CAST(x.f_despacho   AS DATE)
        LEFT JOIN dw.dim_fecha fe ON fe.fecha = CAST(x.f_entrega    AS DATE)
        LEFT JOIN dw.dim_fecha fs ON fs.fecha = CAST(x.f_estimada   AS DATE)
        LEFT JOIN dw.dim_cliente dc       ON dc.customer_unique_id = x.customer_unique_id
        LEFT JOIN dw.dim_ubicacion du     ON du.codigo_postal_prefijo = x.cp
                                         AND du.municipio = x.municipio
                                         AND du.estado    = x.estado
        LEFT JOIN dw.dim_estado_pedido de ON de.codigo = x.order_status
    )
    MERGE dw.fact_pedidos AS d
    USING origen AS o
       ON d.order_id = o.order_id
    WHEN MATCHED AND EXISTS (
            SELECT o.sk_fecha_compra, o.sk_fecha_aprobacion, o.sk_fecha_despacho, o.sk_fecha_entrega, o.sk_fecha_estimada,
                   o.sk_cliente, o.sk_ubicacion_cliente, o.sk_estado_pedido, o.cant_items, o.tiene_items, o.tiene_pago,
                   o.monto_pagado, o.horas_aprobacion, o.dias_despacho, o.dias_entrega, o.dias_retraso, o.entrega_tardia
            EXCEPT
            SELECT d.sk_fecha_compra, d.sk_fecha_aprobacion, d.sk_fecha_despacho, d.sk_fecha_entrega, d.sk_fecha_estimada,
                   d.sk_cliente, d.sk_ubicacion_cliente, d.sk_estado_pedido, d.cant_items, d.tiene_items, d.tiene_pago,
                   d.monto_pagado, d.horas_aprobacion, d.dias_despacho, d.dias_entrega, d.dias_retraso, d.entrega_tardia
         ) THEN
        UPDATE SET sk_fecha_compra      = o.sk_fecha_compra,
                   sk_fecha_aprobacion  = o.sk_fecha_aprobacion,
                   sk_fecha_despacho    = o.sk_fecha_despacho,
                   sk_fecha_entrega     = o.sk_fecha_entrega,
                   sk_fecha_estimada    = o.sk_fecha_estimada,
                   sk_cliente           = o.sk_cliente,
                   sk_ubicacion_cliente = o.sk_ubicacion_cliente,
                   sk_estado_pedido     = o.sk_estado_pedido,
                   cant_items           = o.cant_items,
                   tiene_items          = o.tiene_items,
                   tiene_pago           = o.tiene_pago,
                   monto_pagado         = o.monto_pagado,
                   horas_aprobacion     = o.horas_aprobacion,
                   dias_despacho        = o.dias_despacho,
                   dias_entrega         = o.dias_entrega,
                   dias_retraso         = o.dias_retraso,
                   entrega_tardia       = o.entrega_tardia,
                   fecha_carga          = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (order_id, sk_fecha_compra, sk_fecha_aprobacion, sk_fecha_despacho, sk_fecha_entrega, sk_fecha_estimada,
                sk_cliente, sk_ubicacion_cliente, sk_estado_pedido, cant_items, tiene_items, tiene_pago, monto_pagado,
                horas_aprobacion, dias_despacho, dias_entrega, dias_retraso, entrega_tardia)
        VALUES (o.order_id, o.sk_fecha_compra, o.sk_fecha_aprobacion, o.sk_fecha_despacho, o.sk_fecha_entrega, o.sk_fecha_estimada,
                o.sk_cliente, o.sk_ubicacion_cliente, o.sk_estado_pedido, o.cant_items, o.tiene_items, o.tiene_pago, o.monto_pagado,
                o.horas_aprobacion, o.dias_despacho, o.dias_entrega, o.dias_retraso, o.entrega_tardia)
    OUTPUT $action INTO @acciones;

    SELECT 'fact_pedidos' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 6) fact_ventas — 1 fila = 1 ítem de un pedido (D2, D7, D10, D13, D18, D27)
--    Solo montos del producto. Misma regla D24 que fact_pedidos para la
--    fecha de entrega (grupo Cancelado -> no se usa).
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_fact_ventas
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH ventas AS (
        SELECT
            i.order_id,
            CAST(i.order_item_id AS SMALLINT)  AS order_item_id,
            i.product_id,
            i.seller_id,
            i.price                            AS precio,
            i.freight_value                    AS flete,
            o.order_status,
            o.order_purchase_timestamp         AS f_compra,
            CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN NULL   -- D24: manda el estado
                 ELSE o.order_delivered_customer_date END AS f_entrega,
            c.customer_unique_id,
            c.customer_zip_code_prefix               AS cp_cliente,
            COALESCE(c.municipio, 'sin_municipio')   AS municipio_cliente,
            c.estado                                 AS estado_cliente,
            s.seller_zip_code_prefix                 AS cp_vendedor,
            COALESCE(s.municipio, 'sin_municipio')   AS municipio_vendedor,
            s.estado                                 AS estado_vendedor
        FROM stg.order_items i
        LEFT JOIN stg.orders o    ON o.order_id    = i.order_id
        LEFT JOIN stg.customers c ON c.customer_id = o.customer_id
        LEFT JOIN stg.sellers s   ON s.seller_id   = i.seller_id
    ),
    origen AS (
        SELECT
            v.order_id,
            v.order_item_id,
            COALESCE(fc.sk_fecha, -1)          AS sk_fecha_compra,
            COALESCE(fe.sk_fecha, -1)          AS sk_fecha_entrega,
            COALESCE(dc.sk_cliente, -1)        AS sk_cliente,
            COALESCE(uc.sk_ubicacion, -1)      AS sk_ubicacion_cliente,
            COALESCE(uv.sk_ubicacion, -1)      AS sk_ubicacion_vendedor,
            COALESCE(dp.sk_producto, -1)       AS sk_producto,
            COALESCE(dv.sk_vendedor, -1)       AS sk_vendedor,
            COALESCE(de.sk_estado_pedido, -1)  AS sk_estado_pedido,
            v.precio,
            v.flete
        FROM ventas v
        LEFT JOIN dw.dim_fecha fc ON fc.fecha = CAST(v.f_compra  AS DATE)
        LEFT JOIN dw.dim_fecha fe ON fe.fecha = CAST(v.f_entrega AS DATE)
        LEFT JOIN dw.dim_cliente dc ON dc.customer_unique_id = v.customer_unique_id
        LEFT JOIN dw.dim_ubicacion uc ON uc.codigo_postal_prefijo = v.cp_cliente
                                     AND uc.municipio = v.municipio_cliente
                                     AND uc.estado    = v.estado_cliente
        LEFT JOIN dw.dim_ubicacion uv ON uv.codigo_postal_prefijo = v.cp_vendedor
                                     AND uv.municipio = v.municipio_vendedor
                                     AND uv.estado    = v.estado_vendedor
        LEFT JOIN dw.dim_producto dp      ON dp.product_id = v.product_id
        LEFT JOIN dw.dim_vendedor dv      ON dv.seller_id  = v.seller_id
        LEFT JOIN dw.dim_estado_pedido de ON de.codigo     = v.order_status
    )
    MERGE dw.fact_ventas AS d
    USING origen AS o
       ON  d.order_id      = o.order_id
       AND d.order_item_id = o.order_item_id
    WHEN MATCHED AND EXISTS (
            SELECT o.sk_fecha_compra, o.sk_fecha_entrega, o.sk_cliente, o.sk_ubicacion_cliente, o.sk_ubicacion_vendedor,
                   o.sk_producto, o.sk_vendedor, o.sk_estado_pedido, o.precio, o.flete
            EXCEPT
            SELECT d.sk_fecha_compra, d.sk_fecha_entrega, d.sk_cliente, d.sk_ubicacion_cliente, d.sk_ubicacion_vendedor,
                   d.sk_producto, d.sk_vendedor, d.sk_estado_pedido, d.precio, d.flete
         ) THEN
        UPDATE SET sk_fecha_compra       = o.sk_fecha_compra,
                   sk_fecha_entrega      = o.sk_fecha_entrega,
                   sk_cliente            = o.sk_cliente,
                   sk_ubicacion_cliente  = o.sk_ubicacion_cliente,
                   sk_ubicacion_vendedor = o.sk_ubicacion_vendedor,
                   sk_producto           = o.sk_producto,
                   sk_vendedor           = o.sk_vendedor,
                   sk_estado_pedido      = o.sk_estado_pedido,
                   precio                = o.precio,
                   flete                 = o.flete,
                   fecha_carga           = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (order_id, order_item_id, sk_fecha_compra, sk_fecha_entrega, sk_cliente, sk_ubicacion_cliente,
                sk_ubicacion_vendedor, sk_producto, sk_vendedor, sk_estado_pedido, precio, flete)
        VALUES (o.order_id, o.order_item_id, o.sk_fecha_compra, o.sk_fecha_entrega, o.sk_cliente, o.sk_ubicacion_cliente,
                o.sk_ubicacion_vendedor, o.sk_producto, o.sk_vendedor, o.sk_estado_pedido, o.precio, o.flete)
    OUTPUT $action INTO @acciones;

    SELECT 'fact_ventas' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 7) fact_pagos — 1 fila = 1 pago (D3, D4, D11, D12, D24)
--    Fecha del pago = aprobación; si es nula, compra (origen_fecha).
--    Cuotas ya vienen NULL desde plata cuando Olist puso 0 (D24).
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_fact_pagos
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @acciones TABLE (accion NVARCHAR(10));

    WITH pagos AS (
        SELECT
            p.order_id,
            CAST(p.payment_sequential AS SMALLINT)       AS payment_sequential,
            p.payment_type,
            p.payment_value                              AS monto_pago,
            CAST(p.payment_installments AS SMALLINT)     AS cuotas,
            COALESCE(o.order_approved_at, o.order_purchase_timestamp) AS f_pago,
            CASE WHEN o.order_approved_at IS NOT NULL THEN 'aprobacion' ELSE 'compra' END AS origen_fecha,
            c.customer_unique_id,
            c.customer_zip_code_prefix             AS cp,
            COALESCE(c.municipio, 'sin_municipio') AS municipio,
            c.estado
        FROM stg.payments p
        LEFT JOIN stg.orders o    ON o.order_id    = p.order_id
        LEFT JOIN stg.customers c ON c.customer_id = o.customer_id
    ),
    origen AS (
        SELECT
            x.order_id,
            x.payment_sequential,
            COALESCE(f.sk_fecha, -1)        AS sk_fecha_pago,
            COALESCE(dc.sk_cliente, -1)     AS sk_cliente,
            COALESCE(du.sk_ubicacion, -1)   AS sk_ubicacion_cliente,
            COALESCE(dm.sk_medio_pago, -1)  AS sk_medio_pago,
            x.monto_pago,
            x.cuotas,
            x.origen_fecha
        FROM pagos x
        LEFT JOIN dw.dim_fecha f        ON f.fecha = CAST(x.f_pago AS DATE)
        LEFT JOIN dw.dim_cliente dc     ON dc.customer_unique_id = x.customer_unique_id
        LEFT JOIN dw.dim_ubicacion du   ON du.codigo_postal_prefijo = x.cp
                                       AND du.municipio = x.municipio
                                       AND du.estado    = x.estado
        LEFT JOIN dw.dim_medio_pago dm  ON dm.codigo = x.payment_type
    )
    MERGE dw.fact_pagos AS d
    USING origen AS o
       ON  d.order_id           = o.order_id
       AND d.payment_sequential = o.payment_sequential
    WHEN MATCHED AND EXISTS (
            SELECT o.sk_fecha_pago, o.sk_cliente, o.sk_ubicacion_cliente, o.sk_medio_pago, o.monto_pago, o.cuotas, o.origen_fecha
            EXCEPT
            SELECT d.sk_fecha_pago, d.sk_cliente, d.sk_ubicacion_cliente, d.sk_medio_pago, d.monto_pago, d.cuotas, d.origen_fecha
         ) THEN
        UPDATE SET sk_fecha_pago        = o.sk_fecha_pago,
                   sk_cliente           = o.sk_cliente,
                   sk_ubicacion_cliente = o.sk_ubicacion_cliente,
                   sk_medio_pago        = o.sk_medio_pago,
                   monto_pago           = o.monto_pago,
                   cuotas               = o.cuotas,
                   origen_fecha         = o.origen_fecha,
                   fecha_carga          = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (order_id, payment_sequential, sk_fecha_pago, sk_cliente, sk_ubicacion_cliente, sk_medio_pago,
                monto_pago, cuotas, origen_fecha)
        VALUES (o.order_id, o.payment_sequential, o.sk_fecha_pago, o.sk_cliente, o.sk_ubicacion_cliente, o.sk_medio_pago,
                o.monto_pago, o.cuotas, o.origen_fecha)
    OUTPUT $action INTO @acciones;

    SELECT 'fact_pagos' AS tabla,
           COUNT(CASE WHEN accion = 'INSERT' THEN 1 END) AS insertadas,
           COUNT(CASE WHEN accion = 'UPDATE' THEN 1 END) AS actualizadas
    FROM @acciones;
END;
GO

-- ---------------------------------------------------------------------
-- 8) Maestro — llama a los 7 en orden dentro de UNA transacción (D33).
--    Si cualquiera falla, se deshace todo: dw nunca queda a medias.
--    ADF solo llama a este procedimiento.
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dw.usp_cargar_oro
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Dimensiones
        EXEC dw.usp_cargar_dim_producto;
        EXEC dw.usp_cargar_dim_vendedor;
        EXEC dw.usp_cargar_dim_ubicacion;
        EXEC dw.usp_cargar_dim_cliente;

        -- 2) Hechos (necesitan las dimensiones ya cargadas)
        EXEC dw.usp_cargar_fact_pedidos;
        EXEC dw.usp_cargar_fact_ventas;
        EXEC dw.usp_cargar_fact_pagos;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
