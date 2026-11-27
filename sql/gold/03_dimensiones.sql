-- =====================================================================
-- 03_dimensiones.sql — Dimensiones del modelo estrella (esquema dw)
-- Llaves sustitutas con IDENTITY; llave de negocio con UNIQUE.
-- Miembro desconocido (sk = -1) en cada dimensión (regla general 2).
-- SCD1: los procedimientos de carga sobrescriben (regla general 3).
-- Se puede ejecutar completo de una vez. Borra primero los hechos porque
-- dependen de las dimensiones (claves foráneas).
-- =====================================================================

DROP TABLE IF EXISTS dw.fact_ventas, dw.fact_pagos, dw.fact_pedidos;
DROP TABLE IF EXISTS dw.dim_cliente, dw.dim_ubicacion, dw.dim_producto, dw.dim_vendedor,
                     dw.dim_medio_pago, dw.dim_estado_pedido, dw.ref_region_estado;

-- ---------------------------------------------------------------------
-- Referencia: estado -> región oficial de Brasil (5 regiones, 27 UF)
-- ---------------------------------------------------------------------
CREATE TABLE dw.ref_region_estado (
    estado         CHAR(2)      NOT NULL PRIMARY KEY,
    nombre_estado  VARCHAR(30)  NOT NULL,
    region         VARCHAR(15)  NOT NULL
);
INSERT INTO dw.ref_region_estado (estado, nombre_estado, region) VALUES
('AC','Acre','Norte'),('AM','Amazonas','Norte'),('AP','Amapa','Norte'),('PA','Para','Norte'),
('RO','Rondonia','Norte'),('RR','Roraima','Norte'),('TO','Tocantins','Norte'),
('AL','Alagoas','Nordeste'),('BA','Bahia','Nordeste'),('CE','Ceara','Nordeste'),('MA','Maranhao','Nordeste'),
('PB','Paraiba','Nordeste'),('PE','Pernambuco','Nordeste'),('PI','Piaui','Nordeste'),
('RN','Rio Grande do Norte','Nordeste'),('SE','Sergipe','Nordeste'),
('DF','Distrito Federal','Centro-Oeste'),('GO','Goias','Centro-Oeste'),
('MS','Mato Grosso do Sul','Centro-Oeste'),('MT','Mato Grosso','Centro-Oeste'),
('ES','Espirito Santo','Sudeste'),('MG','Minas Gerais','Sudeste'),('RJ','Rio de Janeiro','Sudeste'),('SP','Sao Paulo','Sudeste'),
('PR','Parana','Sur'),('RS','Rio Grande do Sul','Sur'),('SC','Santa Catarina','Sur');

-- ---------------------------------------------------------------------
-- dim_cliente: 1 fila = 1 persona (customer_unique_id, D5)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_cliente (
    sk_cliente            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    customer_unique_id    VARCHAR(32)  NOT NULL UNIQUE,
    fecha_primera_compra  DATE         NULL,
    num_pedidos           INT          NOT NULL DEFAULT 0,
    es_recurrente         BIT          NOT NULL DEFAULT 0,
    fecha_carga           DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ---------------------------------------------------------------------
-- dim_ubicacion: 1 fila = (CP, municipio, estado) (D31, D32)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_ubicacion (
    sk_ubicacion           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    codigo_postal_prefijo  CHAR(5)       NOT NULL,
    municipio              VARCHAR(100)  NOT NULL,   -- 'sin_municipio' en los 6 casos de D31
    cod_municipio_ibge     INT           NULL,
    estado                 CHAR(2)       NOT NULL,
    region                 VARCHAR(15)   NOT NULL,
    fecha_carga            DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_dim_ubicacion UNIQUE (codigo_postal_prefijo, municipio, estado)
);

-- ---------------------------------------------------------------------
-- dim_producto: 1 fila = 1 producto (R8 / D14 para la categoría)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_producto (
    sk_producto     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    product_id      VARCHAR(32)   NOT NULL UNIQUE,
    categoria_pt    VARCHAR(100)  NOT NULL,   -- 'sin_categoria' si viene nula
    categoria_en    VARCHAR(100)  NOT NULL,   -- 'sin_traduccion' si no hay traducción
    peso_g          INT           NULL,       -- NULL si era 0 (D22)
    largo_cm        INT           NULL,
    alto_cm         INT           NULL,
    ancho_cm        INT           NULL,
    cantidad_fotos  SMALLINT      NULL,
    fecha_carga     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ---------------------------------------------------------------------
-- dim_vendedor: 1 fila = 1 vendedor (ubicación desnormalizada, D19; municipio D31/D32)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_vendedor (
    sk_vendedor         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    seller_id           VARCHAR(32)   NOT NULL UNIQUE,
    municipio           VARCHAR(100)  NOT NULL,
    cod_municipio_ibge  INT           NULL,
    estado              CHAR(2)       NOT NULL,   -- corregido (H-S6)
    region              VARCHAR(15)   NOT NULL,
    fecha_carga         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ---------------------------------------------------------------------
-- dim_medio_pago y dim_estado_pedido: tablas fijas (llave sin IDENTITY)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_medio_pago (
    sk_medio_pago  INT          NOT NULL PRIMARY KEY,
    codigo         VARCHAR(20)  NOT NULL UNIQUE,
    nombre         VARCHAR(30)  NOT NULL,
    categoria      VARCHAR(20)  NOT NULL
);
INSERT INTO dw.dim_medio_pago (sk_medio_pago, codigo, nombre, categoria) VALUES
(-1, 'desconocido', 'Desconocido',        'Sin dato'),
( 1, 'credit_card', 'Tarjeta de credito', 'Tarjeta'),
( 2, 'debit_card',  'Tarjeta de debito',  'Tarjeta'),
( 3, 'boleto',      'Boleto bancario',    'Efectivo'),
( 4, 'voucher',     'Voucher',            'Descuento'),
( 5, 'not_defined', 'No definido',        'Sin dato');

CREATE TABLE dw.dim_estado_pedido (
    sk_estado_pedido  INT          NOT NULL PRIMARY KEY,
    codigo            VARCHAR(20)  NOT NULL UNIQUE,
    nombre            VARCHAR(30)  NOT NULL,
    grupo             VARCHAR(20)  NOT NULL
);
INSERT INTO dw.dim_estado_pedido (sk_estado_pedido, codigo, nombre, grupo) VALUES
(-1, 'desconocido', 'Desconocido',    'Sin dato'),
( 1, 'delivered',   'Entregado',      'Completado'),
( 2, 'canceled',    'Cancelado',      'Cancelado'),
( 3, 'unavailable', 'No disponible',  'Cancelado'),
( 4, 'created',     'Creado',         'En proceso'),
( 5, 'approved',    'Aprobado',       'En proceso'),
( 6, 'invoiced',    'Facturado',      'En proceso'),
( 7, 'processing',  'En preparacion', 'En proceso'),
( 8, 'shipped',     'Enviado',        'En proceso');

-- ---------------------------------------------------------------------
-- Miembro desconocido (-1) en las dimensiones con IDENTITY
-- ---------------------------------------------------------------------
SET IDENTITY_INSERT dw.dim_cliente ON;
INSERT INTO dw.dim_cliente (sk_cliente, customer_unique_id, num_pedidos, es_recurrente) VALUES (-1, 'DESCONOCIDO', 0, 0);
SET IDENTITY_INSERT dw.dim_cliente OFF;

SET IDENTITY_INSERT dw.dim_ubicacion ON;
INSERT INTO dw.dim_ubicacion (sk_ubicacion, codigo_postal_prefijo, municipio, estado, region) VALUES (-1, '00000', 'desconocido', 'XX', 'Desconocida');
SET IDENTITY_INSERT dw.dim_ubicacion OFF;

SET IDENTITY_INSERT dw.dim_producto ON;
INSERT INTO dw.dim_producto (sk_producto, product_id, categoria_pt, categoria_en) VALUES (-1, 'DESCONOCIDO', 'desconocido', 'unknown');
SET IDENTITY_INSERT dw.dim_producto OFF;

SET IDENTITY_INSERT dw.dim_vendedor ON;
INSERT INTO dw.dim_vendedor (sk_vendedor, seller_id, municipio, estado, region) VALUES (-1, 'DESCONOCIDO', 'desconocido', 'XX', 'Desconocida');
SET IDENTITY_INSERT dw.dim_vendedor OFF;

-- Verificación: cada dimensión debe tener su fila -1
SELECT 'dim_cliente' AS dimension, COUNT(*) AS filas FROM dw.dim_cliente UNION ALL
SELECT 'dim_ubicacion', COUNT(*) FROM dw.dim_ubicacion UNION ALL
SELECT 'dim_producto', COUNT(*) FROM dw.dim_producto UNION ALL
SELECT 'dim_vendedor', COUNT(*) FROM dw.dim_vendedor UNION ALL
SELECT 'dim_medio_pago', COUNT(*) FROM dw.dim_medio_pago UNION ALL      -- 6
SELECT 'dim_estado_pedido', COUNT(*) FROM dw.dim_estado_pedido UNION ALL -- 9
SELECT 'ref_region_estado', COUNT(*) FROM dw.ref_region_estado;          -- 27
