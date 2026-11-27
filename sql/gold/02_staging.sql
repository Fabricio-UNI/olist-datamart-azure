-- =====================================================================
-- 02_staging.sql — Tablas stg.* (copia 1 a 1 de plata)
-- Sin restricciones a propósito: staging acepta lo que llega; las
-- validaciones ya se hicieron en plata. ADF las vacía (TRUNCATE) y las
-- recarga con la actividad Copiar en cada ejecución.
-- Los nombres de columna son IGUALES a los de plata: la actividad Copiar
-- mapea por nombre.
-- =====================================================================

DROP TABLE IF EXISTS stg.orders, stg.order_items, stg.payments, stg.products,
                     stg.category_translation, stg.sellers, stg.customers;

CREATE TABLE stg.orders (
    order_id                       VARCHAR(32),
    customer_id                    VARCHAR(32),
    order_status                   VARCHAR(20),
    order_purchase_timestamp       DATETIME2,
    order_approved_at              DATETIME2,
    order_delivered_carrier_date   DATETIME2,
    order_delivered_customer_date  DATETIME2,
    order_estimated_delivery_date  DATETIME2,
    fecha_carga                    DATETIME2
);

CREATE TABLE stg.order_items (
    order_id             VARCHAR(32),
    order_item_id        INT,
    product_id           VARCHAR(32),
    seller_id            VARCHAR(32),
    shipping_limit_date  DATETIME2,
    price                DECIMAL(10,2),
    freight_value        DECIMAL(10,2),
    fecha_carga          DATETIME2
);

CREATE TABLE stg.payments (
    order_id              VARCHAR(32),
    payment_sequential    INT,
    payment_type          VARCHAR(20),
    payment_installments  INT,
    payment_value         DECIMAL(10,2),
    fecha_carga           DATETIME2
);

CREATE TABLE stg.products (
    product_id                  VARCHAR(32),
    product_category_name       VARCHAR(100),
    product_name_lenght         INT,
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            INT,
    product_length_cm           INT,
    product_height_cm           INT,
    product_width_cm            INT,
    fecha_carga                 DATETIME2
);

CREATE TABLE stg.category_translation (
    product_category_name          VARCHAR(100),
    product_category_name_english  VARCHAR(100),
    origen                         VARCHAR(20),
    motivo                         VARCHAR(300),
    fecha_correccion               DATE,
    fecha_carga                    DATETIME2
);

-- seller_city / customer_city en NVARCHAR: es el texto ORIGINAL (puede traer ã, ç, ´)
CREATE TABLE stg.sellers (
    seller_id               VARCHAR(32),
    seller_zip_code_prefix  CHAR(5),
    seller_city             NVARCHAR(100),
    seller_state            VARCHAR(10),
    localidad               VARCHAR(100),
    estado                  CHAR(2),
    municipio               VARCHAR(100),
    cod_municipio_ibge      INT,
    metodo_ciudad           VARCHAR(40),
    fecha_carga             DATETIME2
);

CREATE TABLE stg.customers (
    customer_id               VARCHAR(32),
    customer_unique_id        VARCHAR(32),
    customer_zip_code_prefix  CHAR(5),
    customer_city             NVARCHAR(100),
    customer_state            VARCHAR(10),
    localidad                 VARCHAR(100),
    estado                    CHAR(2),
    municipio                 VARCHAR(100),
    cod_municipio_ibge        INT,
    metodo_ciudad             VARCHAR(40),
    fecha_carga               DATETIME2
);

SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'stg' ORDER BY TABLE_NAME;
