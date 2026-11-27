-- =====================================================================
-- 06_verificar_sellers.sql — Verificación de silver/olist/sellers/
-- Motor: Synapse SQL serverless, base olist_perfilamiento (data source silver_olist)
-- Escrito por: df_silver_sellers = sellers (bronce) LEFT JOIN mapa_ciudades (D29-D31)
-- por (seller_city, estado en mayúsculas, CP). Base de dim_vendedor y de la
-- ubicación del vendedor en dim_ubicacion.
-- Si en el flujo la columna quedó como metodo_ibge, cambiar metodo_ciudad abajo.
-- =====================================================================

-- 1) Tipos: el CP debe ser texto (varchar), no número (R1, H-S2)
SELECT column_ordinal, name, system_type_name
FROM sys.dm_exec_describe_first_result_set(N'
SELECT * FROM OPENROWSET(BULK ''sellers/*.parquet'', DATA_SOURCE = ''silver_olist'',
     FORMAT = ''PARQUET'') AS r', NULL, 0);

-- 2) Conteos y calidad del join con el mapa
--    Resultado (26/11/2026): 3,095 / 3,095 / 0 / 0 / 0 / 34 vendedores con el estado corregido (H-S6).
SELECT
    COUNT(*)                                                         AS vendedores,          -- esperado 3,095 (H-S1)
    COUNT(DISTINCT seller_id)                                        AS vendedores_unicos,   -- esperado 3,095
    SUM(CASE WHEN LEN(seller_zip_code_prefix) <> 5 THEN 1 ELSE 0 END) AS cp_sin_5_digitos,   -- esperado 0 (antes 1,027 por la inferencia)
    SUM(CASE WHEN localidad IS NULL THEN 1 ELSE 0 END)               AS sin_fila_en_mapa,    -- esperado 0
    SUM(CASE WHEN municipio IS NULL THEN 1 ELSE 0 END)               AS sin_municipio,       -- esperado 0 o muy pocos (de los 6 de D31)
    SUM(CASE WHEN estado <> UPPER(LTRIM(RTRIM(seller_state))) THEN 1 ELSE 0 END) AS estado_corregido  -- H-S6
FROM OPENROWSET(BULK 'sellers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r;

-- 3) Cómo se resolvió la ciudad de los vendedores
SELECT metodo_ciudad, COUNT(*) AS vendedores
FROM OPENROWSET(BULK 'sellers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
GROUP BY metodo_ciudad
ORDER BY vendedores DESC;

-- 4) La prueba de fuego (H-S3): las 7 formas de escribir São Paulo ahora son UN municipio
--    Resultado (26/11/2026): 9 formas (no 7) -> municipio sao paulo, 705 vendedores (694 + 11).
--    Trampas bien resueltas: jacarei, maua, ribeirao preto, santo andre, carapicuiba (estado pegado);
--    sbc -> sao bernardo do campo; sp -> aracatuba y braganca paulista segun CP (D30); paulo lopes (SC) intacta.
SELECT seller_city AS escrito, municipio, estado, COUNT(*) AS vendedores
FROM OPENROWSET(BULK 'sellers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS r
WHERE seller_city LIKE '%paulo%' OR seller_city IN ('sp', 'sp / sp', 'sbc/sp')
GROUP BY seller_city, municipio, estado
ORDER BY municipio, vendedores DESC;

-- 5) Integridad: todo vendedor de order_items existe en plata (esperado 0, H-I5)
SELECT COUNT(*) AS items_sin_vendedor
FROM OPENROWSET(BULK 'order_items/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS i
LEFT JOIN OPENROWSET(BULK 'sellers/*.parquet', DATA_SOURCE = 'silver_olist', FORMAT = 'PARQUET') AS s
       ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL;
