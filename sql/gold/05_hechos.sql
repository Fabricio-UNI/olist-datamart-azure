-- =====================================================================
-- 05_hechos.sql — Tablas de hechos (esquema dw), según D25, D26 y D27
-- Claves foráneas a todas las dimensiones: ningún hecho puede apuntar a
-- una dimensión inexistente (lo que no se encuentre va al miembro -1).
-- Ejecutar DESPUÉS de 03 y 04. Se puede ejecutar completo de una vez.
-- =====================================================================

DROP TABLE IF EXISTS dw.fact_ventas, dw.fact_pagos, dw.fact_pedidos;

-- ---------------------------------------------------------------------
-- fact_ventas: 1 fila = 1 producto vendido en un pedido (grano: ítem)
-- Solo montos del producto (D27). Los tiempos de entrega están en fact_pedidos.
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_ventas (
    order_id               VARCHAR(32)    NOT NULL,   -- dimensión degenerada
    order_item_id          SMALLINT       NOT NULL,   -- dimensión degenerada
    sk_fecha_compra        INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),
    sk_fecha_entrega       INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),   -- -1 si no hay (D24)
    sk_cliente             INT            NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_ubicacion_cliente   INT            NOT NULL REFERENCES dw.dim_ubicacion (sk_ubicacion),
    sk_ubicacion_vendedor  INT            NOT NULL REFERENCES dw.dim_ubicacion (sk_ubicacion),
    sk_producto            INT            NOT NULL REFERENCES dw.dim_producto (sk_producto),
    sk_vendedor            INT            NOT NULL REFERENCES dw.dim_vendedor (sk_vendedor),
    sk_estado_pedido       INT            NOT NULL REFERENCES dw.dim_estado_pedido (sk_estado_pedido),
    precio                 DECIMAL(10,2)  NOT NULL,   -- aditivo
    flete                  DECIMAL(10,2)  NOT NULL,   -- aditivo
    fecha_carga            DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_fact_ventas PRIMARY KEY (order_id, order_item_id)
);

-- ---------------------------------------------------------------------
-- fact_pagos: 1 fila = 1 pago (grano: order_id + payment_sequential)
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_pagos (
    order_id              VARCHAR(32)    NOT NULL,
    payment_sequential    SMALLINT       NOT NULL,
    sk_fecha_pago         INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),     -- aprobación; si es nula, compra (D12)
    sk_cliente            INT            NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_ubicacion_cliente  INT            NOT NULL REFERENCES dw.dim_ubicacion (sk_ubicacion),
    sk_medio_pago         INT            NOT NULL REFERENCES dw.dim_medio_pago (sk_medio_pago),
    monto_pago            DECIMAL(10,2)  NOT NULL,   -- aditivo
    cuotas                SMALLINT       NULL,       -- no aditivo; NULL si venía 0 (R11)
    origen_fecha          VARCHAR(10)    NOT NULL,   -- 'aprobacion' o 'compra'
    fecha_carga           DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_fact_pagos PRIMARY KEY (order_id, payment_sequential)
);

-- ---------------------------------------------------------------------
-- fact_pedidos: 1 fila = 1 pedido (snapshot acumulativo, D26)
-- Tiempos de entrega aquí y no en fact_ventas (D27). Sin montos de venta.
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_pedidos (
    order_id              VARCHAR(32)    NOT NULL PRIMARY KEY,
    sk_fecha_compra       INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),
    sk_fecha_aprobacion   INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),   -- -1 si es nula
    sk_fecha_despacho     INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),   -- -1 si es nula
    sk_fecha_entrega      INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),   -- -1 si es nula o cancelado (D24)
    sk_fecha_estimada     INT            NOT NULL REFERENCES dw.dim_fecha (sk_fecha),
    sk_cliente            INT            NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_ubicacion_cliente  INT            NOT NULL REFERENCES dw.dim_ubicacion (sk_ubicacion),
    sk_estado_pedido      INT            NOT NULL REFERENCES dw.dim_estado_pedido (sk_estado_pedido),
    cant_items            SMALLINT       NOT NULL,   -- aditivo (0 en los 775 sin ítems, D25)
    tiene_items           BIT            NOT NULL,
    tiene_pago            BIT            NOT NULL,   -- 0 solo en bfbd0f9b... (D23)
    monto_pagado          DECIMAL(12,2)  NOT NULL,   -- aditivo (0 si no tiene pago)
    horas_aprobacion      INT            NULL,       -- no aditivo
    dias_despacho         INT            NULL,       -- no aditivo (puede ser negativo: inconsistencia del origen)
    dias_entrega          INT            NULL,       -- no aditivo
    dias_retraso          INT            NULL,       -- no aditivo (positivo = tarde)
    entrega_tardia        TINYINT        NULL,       -- contador: 1 si dias_retraso > 0
    fecha_carga           DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Verificación: las 3 tablas creadas (vacías) y cuántas claves foráneas tiene cada una
SELECT t.name AS hecho, COUNT(fk.object_id) AS claves_foraneas
FROM sys.tables t
LEFT JOIN sys.foreign_keys fk ON fk.parent_object_id = t.object_id
WHERE SCHEMA_NAME(t.schema_id) = 'dw' AND t.name LIKE 'fact_%'
GROUP BY t.name;   -- esperado: fact_ventas 8, fact_pagos 4, fact_pedidos 8
