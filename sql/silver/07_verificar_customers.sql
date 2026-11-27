-- =====================================================================
-- 07_verificar_customers.sql — Verificación de silver/olist/customers/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data source silver_olist)
-- Escrito por: df_silver_customers = customers (bronce) LEFT JOIN mapa_ciudades
-- por (customer_city, estado en mayúsculas, CP). Base de dim_cliente y de la
-- ubicación del cliente en dim_ubicacion. Esperados: H-C1 a H-C9.
-- Si en el flujo la columna quedó como metodo_ibge, cambiar metodo_ciudad abajo.
-- =====================================================================

-- 1) Conteos y calidad del join con el mapa
--    Resultado (26/11/2026): 99,441 / 99,441 / 96,096 personas / 0 / 0 / 12 sin municipio / 0 estados corregidos.
--    Los 34 estados equivocados de H-S6 eran TODOS de vendedores: los clientes escriben bien la ubicacion (H-C8).
SELECT
    COUNT(*)                                                            AS clientes,           -- esperado 99,441 (H-C1)
    COUNT(DISTINCT customer_id)                                         AS customer_id_unicos, -- esperado 99,441
    COUNT(DISTINCT customer_unique_id)                                  AS personas,           -- esperado 96,096 (H-C2)
    SUM(CASE WHEN LEN(customer_zip_code_prefix) <> 5 THEN 1 ELSE 0 END) AS cp_sin_5_digitos,   -- esperado 0 (antes 23,995, H-C6)
    SUM(CASE WHEN localidad IS NULL THEN 1 ELSE 0 END)                  AS sin_fila_en_mapa,   -- esperado 0
    SUM(CASE WHEN municipio IS NULL THEN 1 ELSE 0 END)                  AS sin_municipio,      -- esperado pocos (de los 6 de D31)
    SUM(CASE WHEN estado <> UPPER(LTRIM(RTRIM(customer_state))) THEN 1 ELSE 0 END) AS estado_corregido
FROM OPENROWSET(BULK 'customers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 2) Cómo se resolvió la ciudad de los clientes
SELECT metodo_ciudad, COUNT(*) AS clientes
FROM OPENROWSET(BULK 'customers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
GROUP BY metodo_ciudad
ORDER BY clientes DESC;

-- 3) Los clientes sin municipio (deben ser solo de las 6 localidades de D31)
--    Resultado (26/11/2026): quatro bocas 5 · caraiba 2 · vila nova (PR) 2 · salobro 1 · morada nova 1 · alto sao joao 1 = 12.
SELECT localidad, estado, COUNT(*) AS clientes
FROM OPENROWSET(BULK 'customers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
WHERE municipio IS NULL
GROUP BY localidad, estado;

-- 4) Integridad: todo pedido tiene su cliente en plata, y todo cliente su pedido (H-C9)
SELECT
    (SELECT COUNT(*)
       FROM OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
       LEFT JOIN OPENROWSET(BULK 'customers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS c
              ON o.customer_id = c.customer_id
      WHERE c.customer_id IS NULL) AS pedidos_sin_cliente,   -- esperado 0
    (SELECT COUNT(*)
       FROM OPENROWSET(BULK 'customers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS c
       LEFT JOIN OPENROWSET(BULK 'orders/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS o
              ON c.customer_id = o.customer_id
      WHERE o.customer_id IS NULL) AS clientes_sin_pedido;   -- esperado 0
