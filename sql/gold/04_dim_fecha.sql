-- =====================================================================
-- 04_dim_fecha.sql — Calendario generado (no viene de Olist)
-- 1 fila = 1 día, de 2016-01-01 a 2018-12-31 (cubre compras 2016-09-04 a
-- 2018-10-17 y las fechas de entrega y estimadas). + miembro -1 ("sin fecha"),
-- que usan las fechas de entrega/aprobación/despacho nulas (D24).
-- Se puede ejecutar completo de una vez.
-- =====================================================================

DROP TABLE IF EXISTS dw.fact_ventas, dw.fact_pagos, dw.fact_pedidos;
DROP TABLE IF EXISTS dw.dim_fecha;

CREATE TABLE dw.dim_fecha (
    sk_fecha          INT          NOT NULL PRIMARY KEY,   -- AAAAMMDD, ej. 20170315
    fecha             DATE         NOT NULL,
    anio              SMALLINT     NOT NULL,
    trimestre         SMALLINT     NOT NULL,
    mes               SMALLINT     NOT NULL,
    dia               SMALLINT     NOT NULL,
    nombre_mes        VARCHAR(15)  NOT NULL,
    anio_mes          CHAR(7)      NOT NULL,               -- "2017-03"
    dia_semana        SMALLINT     NOT NULL,               -- 1 = lunes ... 7 = domingo
    nombre_dia        VARCHAR(10)  NOT NULL,
    es_fin_de_semana  BIT          NOT NULL
);

-- Generador de números 0..N sin bucles: ROW_NUMBER sobre un producto cruzado
WITH numeros AS (
    SELECT TOP (DATEDIFF(DAY, '2016-01-01', '2018-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
dias AS (
    SELECT DATEADD(DAY, i, CAST('2016-01-01' AS DATE)) AS d FROM numeros
),
con_dia_semana AS (
    -- (DATEPART(WEEKDAY) + @@DATEFIRST - 2) % 7 + 1 da 1 = lunes sin importar la configuración regional
    SELECT d, (DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7 + 1 AS dsem FROM dias
)
INSERT INTO dw.dim_fecha
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DAY(d),
    CHOOSE(MONTH(d), 'Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
                     'Agosto','Septiembre','Octubre','Noviembre','Diciembre'),
    CONVERT(CHAR(7), d, 126),
    dsem,
    CHOOSE(dsem, 'Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo'),
    CASE WHEN dsem IN (6, 7) THEN 1 ELSE 0 END
FROM con_dia_semana;

-- Miembro desconocido: "sin fecha"
INSERT INTO dw.dim_fecha VALUES (-1, '1900-01-01', 1900, 0, 0, 0, 'Sin fecha', '0000-00', 0, 'Sin fecha', 0);

-- Verificación
SELECT COUNT(*) AS filas,                 -- esperado 1,096 días (2016 es bisiesto: 366 + 365 + 365); con el -1 la tabla tiene 1,097
       MIN(fecha) AS desde, MAX(fecha) AS hasta
FROM dw.dim_fecha WHERE sk_fecha <> -1;
SELECT TOP 7 * FROM dw.dim_fecha WHERE fecha >= '2017-03-13' ORDER BY fecha;  -- 13/03/2017 fue lunes
