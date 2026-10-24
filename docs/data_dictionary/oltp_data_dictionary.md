# Diccionario resumido — OLTP

## `source_system`
Identifica la procedencia lógica de los datos.

## `country`
Catálogo ISO de países utilizado por clientes, emisores y comercios.

## `customer`
Entidad maestra del cliente.

Clave de negocio fuente:

```text
(source_system_id, source_customer_key)
```

## `customer_address`
Dirección y país del cliente.

## `customer_financial_profile`
Perfil financiero historizable del cliente.

## `card`
Tarjeta asociada a un cliente.

Clave fuente:

```text
(source_system_id, source_card_key)
```

Para IBM, `source_card_key` se construirá utilizando usuario + `CARD INDEX`.

## `merchant`
Comercio.

En el dataset IBM el campo llamado `Merchant Name` se comporta como identificador de comercio; por eso se utiliza como `source_merchant_key`.

## `merchant_location`
Ubicación del comercio.

`source_location_key` es una clave técnica determinística utilizada por el ETL para idempotencia.

## `merchant_category`
Clasificación del comercio. Para el núcleo IBM se utilizará esquema `MCC`.

## `authorization_status`
Estado de la autorización:

- APPROVED
- DECLINED
- REVERSED
- PENDING
- ERROR
- UNKNOWN

## `decline_reason`
Motivo de denegación con categoría analítica.

## `card_transaction`
Evento operacional central.

Cada fila representa una transacción/intento presente en la fuente ya integrado al modelo operacional.

La procedencia se identifica mediante:

```text
source_system_id
source_transaction_key
```

Para archivos IBM homogéneos, la clave se generará con hash de archivo + número de fila.

## `transaction_error`
Relación N:M operacional entre una transacción y errores detectados.

Esto evita duplicar la transacción principal cuando una operación contiene más de un error.
