# Perfilamiento de datos — Data Mart Olist

> Revisión de los CSV de la capa **bronce** antes de construir la capa **plata**.
> Las consultas están en [`sql/perfilamiento/`](../sql/perfilamiento/).
> Última actualización: 2026-11-24 · Estado: **completo (7 de 7 tablas)**.

---

## 1. Resumen

| | |
|---|---|
| **Objetivo** | Confirmar con números reales los hallazgos del diseño ([`decisiones_modelo.md`](decisiones_modelo.md)) y descubrir problemas nuevos antes de construir plata |
| **Herramienta** | Azure Synapse **SQL serverless** (`syn-olist-fabri01`), consultando los CSV directo en el data lake con `OPENROWSET`, sin moverlos ni descargarlos |
| **Alcance** | Las 7 tablas que entran al modelo. `reviews` y `geolocation` quedan fuera (D17) |
| **Costo** | Centavos: serverless cobra por datos leídos (~120 MB en total) |

**Conclusión:** los datos son **consistentes en llaves e integridad**: ninguna de las 7 tablas tiene duplicados ni registros huérfanos. Los problemas son puntuales y todos tienen tratamiento: **completitud** (productos sin categoría, fechas y un pago faltantes), **estandarización** (ciudades de vendedores escritas de muchas formas), **valores imposibles** (peso 0, cuotas 0) y, sobre todo, **tipos de datos** cuando se dejan inferir. Las decisiones de diseño D5 y D6 quedaron validadas con datos reales.

---

## 2. Las 4 revisiones

A cada tabla se le aplican las mismas revisiones, siempre pensando en qué parte del modelo alimenta:

| # | Revisión | Pregunta | Por qué importa en el modelo |
|---|---|---|---|
| 1 | **Duplicados** | ¿Se repite la llave? | Una fila repetida infla los hechos o duplica filas al unir con una dimensión |
| 2 | **Nulos** | ¿Faltan datos? ¿Es esperado? | Un nulo esperado se acepta; uno inesperado es un error de datos |
| 3 | **Valores raros** | ¿Hay datos imposibles, fuera de rango o mal escritos? | Montos negativos, pesos en 0 o textos inconsistentes distorsionan los análisis |
| 4 | **Integridad referencial** | ¿Lo que una tabla apunta en otra existe? | Un hecho huérfano cae en el miembro "Desconocido" (`sk = -1`) |

---

## 3. Resultados por tabla

### 3.1 `orders` → `fact_ventas`, `fact_pagos`, `dim_estado_pedido`, `dim_fecha`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-O1 | Duplicados de `order_id` | 0 (99,441 pedidos) | ✅ |
| H-O2 | Fechas de compra inválidas | 0 · rango 2016-09-04 → 2018-10-17 | ✅ Cabe en `dim_fecha` (2016–2018) |
| H-O3 | Estados | 8 estados, suman 99,441 | ✅ Coinciden con `dim_estado_pedido` |
| H-O4 | Pedidos sin fecha de aprobación | 160 | `fact_pagos` usa la fecha de compra y marca `origen_fecha` (D12) |
| H-O5 | Pedidos sin entrega a transportista / al cliente | 1,783 / 2,965 | Nulos esperados en pedidos no entregados (D16) |
| H-O6 | **`delivered` sin fecha de entrega** | **8** | ⚠️ Error de datos. Se conservan: `dias_entrega` NULL en `fact_pedidos` y `sk_fecha_entrega = -1` (D24, D27) |
| H-O7 | **`canceled` con fecha de entrega** (hallazgo nuevo) | **6** | ⚠️ Inconsistencia. Manda el estado; la fecha sobrante no se usa (D24). Consultar al negocio cómo registra devoluciones |
| H-O8 | Entrega anterior a la compra | 0 | ✅ Sospecha descartada |
| H-O9 | Integridad `orders` → `customers` | 0 pedidos sin cliente | ✅ (revisado en `07_customers.sql`) |
| H-O10 | **Pedidos sin ningún ítem** (hallazgo en plata, 24/11) | **775** = unavailable 603 · canceled 164 · created 5 · invoiced 2 · shipped 1 | ⚠️ No generan filas en `fact_ventas` (grano = ítem). Los 3 `invoiced`/`shipped` sin ítems son inconsistencia del origen. "Pedido" = pedido con ítems; medida "Pedidos con venta" (D25) |

Cuadre que reveló H-O7: no entregados = 99,441 − 96,478 = **2,963**; sin fecha de entrega = **2,965** = 8 (H-O6) + 2,957. Faltaban 6.

### 3.2 `order_items` → `fact_ventas` (grano)

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-I1 | Duplicados por llave compuesta (`order_id` + `order_item_id`) | 0 (112,650 ítems) | ✅ |
| H-I2 | Nulos | 0 | ✅ |
| H-I3 | Flete en 0 | 383 | ✅ Valor **válido** (envío gratis): se conserva como 0 |
| H-I4 | Rango de montos | Precio 0.85 – 6,735 (promedio ~120.65) · flete 0 – 409.68 · 0 negativos | ✅ El máximo es atípico pero creíble |
| H-I5 | Integridad: ítems sin pedido / producto / vendedor | 0 / 0 / 0 | ✅ Ninguna venta cae en "Desconocido" |

Total vendido de referencia: **112,650 ítems · R$ 13,591,643.70**.

### 3.3 `products` → `dim_producto`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-P1 | Duplicados de `product_id` | 0 | ✅ |
| H-P2 | **Catálogo incompleto**: sin categoría **y** sin fotos (los mismos productos) | **610** productos · 1,603 ítems vendidos · **1.32% del monto** | `categoria_pt = 'sin_categoria'` (D14). Impacto bajo en el análisis por categoría |
| H-P3 | Sin peso ni medidas (los mismos productos) | 2 | NULL. No afecta preguntas de negocio |
| H-P4 | **Peso 0 gramos** | **4** | Convertir a NULL (D22) |
| H-P5 | Rango de medidas | 7 – 105 cm, ninguna en 0 | ✅ Probablemente medidas del paquete de envío |
| H-P6 | **Categorías sin traducción** | `portateis_cozinha_e_preparadores_de_alimentos` (10) · `pc_gamer` (3) | Tabla de corrección `referencia/correccion_traduccion_categorias.csv` (D21) |

### 3.4 `category_translation` → `dim_producto`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-T1 | Categorías repetidas | 0 | ✅ |
| H-T2 | Traducciones vacías | 0 | ✅ |

### 3.5 `sellers` → `dim_vendedor`, `dim_ubicacion`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-S1 | Duplicados y nulos | 0 · 3,095 vendedores completos | ✅ |
| H-S2 | **Código postal leído como número pierde el 0 a la izquierda** | **1,027 (33%)** | El CSV sí trae el cero: leer siempre como `CHAR(5)` |
| H-S3 | **Ciudades escritas de varias formas** (hallazgo 12) | São Paulo en 7 variantes; otras ciudades con el estado pegado (`carapicuiba / sao paulo`) | Reglas de normalización (sección 5) |
| H-S4 | Estados | 23 válidos, 2 letras en mayúscula · SP concentra el 60% | ✅ |

### 3.6 `payments` → `fact_pagos`, `dim_medio_pago`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-PA1 | Duplicados (`order_id` + `payment_sequential`) | 0 · 103,886 pagos de 99,440 pedidos · **4,446 pagos extra** por pedidos con varios medios | ✅ Confirma el hallazgo 2 |
| H-PA2 | **Pedido `delivered` sin ningún pago** | 1 · `bfbd0f9bdef84302105ad712db648a6c` (2016-09-15, primeros días del dataset) | No se inventa el pago: queda sin filas en `fact_pagos` y aparece en la conciliación (D23) |
| H-PA3 | Pagos `not_defined` con monto 0 | 3 · los 3 pedidos están `canceled` | ✅ Rastro de cancelaciones: se quedan con "No definido" |
| H-PA4 | **Tarjeta de crédito con 0 cuotas** | **2** | Se convierten a NULL: el mínimo es 1 cuota y no se supone un valor (D24) |
| H-PA5 | Vouchers con monto 0 | 6 | ✅ Vouchers sin saldo: se quedan (suman 0) |
| H-PA6 | Medios de pago | Exactamente los 5 de `dim_medio_pago` · tarjeta de crédito: 74% de los pagos y 78% del monto | ✅ |
| H-PA7 | Rangos | Cuotas 0–24 · monto 0–13,664.08 · 0 negativos · 0 nulos | ✅ |
| H-PA8 | Integridad `payments` → `orders` | 0 pagos huérfanos | ✅ |

| Medio | Pagos | Monto |
|---|---|---|
| `credit_card` | 76,795 | R$ 12,542,084.19 |
| `boleto` | 19,784 | R$ 2,869,361.27 |
| `voucher` | 5,775 | R$ 379,436.87 |
| `debit_card` | 1,529 | R$ 217,989.79 |
| `not_defined` | 3 | R$ 0.00 |

En Olist el **voucher es un medio de pago** (vale, saldo a favor, tarjeta de regalo), no un descuento: se registra como una fila de pago y suma a lo pagado.

### 3.7 `customers` → `dim_cliente`, `dim_ubicacion`

| # | Hallazgo | Resultado | Tratamiento |
|---|---|---|---|
| H-C1 | Duplicados de `customer_id` | 0 · 99,441 = mismo número de pedidos (1 por pedido) | ✅ Confirma el hallazgo 4 |
| H-C2 | **Personas reales** (`customer_unique_id`) | **96,096** · 3,345 compras de personas que ya habían comprado | ✅ **Valida D5** |
| H-C3 | **Clientes recurrentes** | **2,997 personas (3.1%)** · máximo 17 pedidos de una persona | `es_recurrente` en `dim_cliente`. Hallazgo de negocio: casi nadie vuelve a comprar |
| H-C4 | Nulos | 0 | ✅ |
| H-C5 | Estados | 27 (todos los de Brasil) | ✅ |
| H-C6 | Código postal leído como número pierde el 0 | **23,995 (24%)** | Leer como `CHAR(5)` (R1) |
| H-C7 | **Personas que compraron desde más de una ciudad** | **122** | ✅ **Valida D6**: la ubicación es del pedido |
| H-C8 | Variantes de São Paulo | Una sola forma (`sao paulo`, 15,540). `sao paulo do potengi`, `sao paulo das missoes` y `morro de sao paulo` son otras ciudades reales | ✅ Más limpio que `sellers` (probablemente lo completa el sistema y no la persona). Ojo con R4 |
| H-C9 | Integridad en los dos sentidos | 0 pedidos sin cliente · 0 clientes sin pedido | ✅ Relación 1 a 1 |

---

## 4. Lecciones transversales: los tipos de datos

Dejar que `OPENROWSET` **infiera** los tipos causó tres problemas distintos:

| Columna | Tipo inferido | Problema | Tipo correcto en plata |
|---|---|---|---|
| `freight_value` | Número | `NULLIF(col, '')` convirtió `''` en 0 y contó los fletes en 0 como nulos | `DECIMAL(10,2)` |
| `price` | `FLOAT` | Errores de redondeo en los centavos (13591643.70**001419**) | `DECIMAL(10,2)` |
| `seller_zip_code_prefix` | Número | Perdió el 0 a la izquierda en el 33% de los vendedores | `CHAR(5)` |

**Reglas que salen de aquí:**
1. En plata, cada columna se lee con su **tipo declarado** (`WITH` en `OPENROWSET`, esquema explícito en Data Factory). Nunca se deja adivinar.
2. El **dinero** va en `DECIMAL`, nunca en `FLOAT`.
3. Los **identificadores numéricos** (códigos postales, DNI, teléfonos) son **texto**: no se hacen cuentas con ellos.
4. `NULLIF(col, '')` solo en columnas de **texto**.

---

## 5. Reglas de limpieza para plata

Lo que Data Factory tendrá que aplicar al pasar de bronce a plata:

| # | Regla | Origen |
|---|---|---|
| R1 | Declarar los tipos de todas las columnas (dinero `DECIMAL(10,2)`, códigos postales `CHAR(5)`, fechas `DATETIME2`) | Sección 4 |
| R2 | Ciudades: quitar espacios al inicio y final, pasar a minúsculas | H-S3 |
| R3 | Ciudades: quitar tildes (`são` → `sao`) | H-S3 |
| R4 | Ciudades: quitar el estado pegado **al final** (`- sp`, ` sp`, `/ sao paulo`) sin confundir la ciudad con el estado y sin romper ciudades reales como `sao paulo do potengi` o `morro de sao paulo` | H-S3, H-C8 |
| R5 | Ciudades: corregir errores de tipeo con una tabla de corrección (ej. `sao paulop`) | H-S3 |
| R6 | Peso 0 → NULL | H-P4, D22 |
| R7 | Completar traducciones con `referencia/correccion_traduccion_categorias.csv` | H-P6, D21 |
| R8 | Categoría nula → `sin_categoria`; sin traducción → `sin_traduccion` | H-P2, D14 |
| R9 | Flete 0 se conserva (es válido) | H-I3 |
| R10 | Pedidos `delivered` sin fecha y `canceled` con fecha: se conservan y se reportan en el registro de calidad | H-O6, H-O7, D24 |
| R11 | Cuotas 0 → NULL | H-PA4, D24 |
| R12 | Conciliación por pedido: lo pagado debe ser **igual o mayor** a lo vendido (intereses por cuotas). Pagado menor o sin pago → alerta de calidad | H-PA2, D23 |

---

## 6. Pendientes

- [x] Perfilar `payments`.
- [x] Perfilar `customers`.
- [x] Confirmar el tratamiento de H-O6, H-O7 y H-PA4 (D24).
- [ ] Revisar ciudades de `customers` más allá de São Paulo (solo se revisó esa ciudad).
- [ ] Ejecutar la conciliación ventas vs. pagos (R12) cuando existan `fact_ventas` y `fact_pagos`.
