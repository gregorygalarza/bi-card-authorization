/*
===============================================================================
01_create_dimensional_model.sql

Proyecto:
    Denegación de Transacciones Internacionales

Precondición:
    El schema olap debe haber sido creado previamente por los scripts
    de inicialización de la base de datos.

Objetivo:
    Crear el modelo dimensional OLAP utilizado posteriormente por Power BI.

Modelo:
    Esquema estrella con UNA ÚNICA TABLA DE HECHOS:
        olap.fact_transaction

Granularidad:
    Una fila en fact_transaction por cada intento de transacción/autorización
    existente en oltp.card_transaction.

Decisiones de diseño:
    - Las dimensiones utilizan claves sustitutas (surrogate keys).
    - Los identificadores del OLTP se conservan solamente para trazabilidad.
    - Una transacción operacional puede contener múltiples errores.
      El OLTP conserva todos ellos mediante oltp.transaction_error.
    - Para preservar una única tabla de hechos en el modelo dimensional,
      fact_transaction utilizará primary_error_key, correspondiente al error
      principal determinado mediante la prioridad configurada en las reglas
      de integración.
    - Las dimensiones serán inicialmente Tipo 1.
    - Los índices analíticos adicionales se crearán después de la carga
      inicial para no penalizar el ETL masivo.
===============================================================================
*/


/*
===============================================================================
1. DIM_DATE

Clave:
    YYYYMMDD

Ejemplo:
    20261029
===============================================================================
*/

CREATE TABLE olap.dim_date (
    date_key                integer PRIMARY KEY,

    full_date               date NOT NULL UNIQUE,

    year_number             smallint NOT NULL,
    quarter_number          smallint NOT NULL,
    month_number            smallint NOT NULL,
    month_name              varchar(20) NOT NULL,

    day_of_month            smallint NOT NULL,
    day_of_week             smallint NOT NULL,
    day_name                varchar(20) NOT NULL,

    is_weekend              boolean NOT NULL,

    CONSTRAINT ck_dim_date_quarter
        CHECK (quarter_number BETWEEN 1 AND 4),

    CONSTRAINT ck_dim_date_month
        CHECK (month_number BETWEEN 1 AND 12),

    CONSTRAINT ck_dim_date_day_of_month
        CHECK (day_of_month BETWEEN 1 AND 31),

    CONSTRAINT ck_dim_date_day_of_week
        CHECK (day_of_week BETWEEN 1 AND 7)
);


/*
===============================================================================
2. DIM_CUSTOMER

Dimensión analítica a nivel cliente.

Se desnormalizan:
    - datos básicos del cliente
    - dirección vigente
    - perfil financiero vigente

Esto evita reproducir en Power BI la estructura normalizada del OLTP.
===============================================================================
*/

CREATE TABLE olap.dim_customer (
    customer_key            integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    source_system_code      varchar(30) NOT NULL,
    source_customer_key     varchar(100) NOT NULL,

    full_name               varchar(200),
    first_name              varchar(100),
    last_name               varchar(100),

    gender                  varchar(30),

    current_age             smallint,
    retirement_age          smallint,

    birth_year              smallint,
    birth_month             smallint,

    city                    varchar(120),
    state_code              varchar(30),
    postal_code             varchar(30),
    country_code            varchar(2),

    annual_income           numeric(18,2),
    total_debt              numeric(18,2),
    credit_score            smallint,
    cards_count             smallint,

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_customer_source
        UNIQUE (
            source_system_code,
            source_customer_key
        )
);


/*
===============================================================================
3. DIM_CARD
===============================================================================
*/

CREATE TABLE olap.dim_card (
    card_key                integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    source_system_code      varchar(30) NOT NULL,
    source_card_key         varchar(120) NOT NULL,

    card_brand              varchar(50),
    card_type               varchar(50),

    has_chip                boolean,

    credit_limit            numeric(18,2),

    opened_date             date,
    expiration_date         date,

    issuer_country_code     varchar(2),

    dark_web_flag           boolean,

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_card_source
        UNIQUE (
            source_system_code,
            source_card_key
        )
);


/*
===============================================================================
4. DIM_MERCHANT

El merchant_source_identifier proveniente del dataset IBM corresponde a un identificador
opaco de comercio, pero se conserva como atributo descriptivo trazable.
===============================================================================
*/

CREATE TABLE olap.dim_merchant (
    merchant_key            integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    source_system_code          varchar(30) NOT NULL,
    source_merchant_key         varchar(150) NOT NULL,

    merchant_source_identifier  varchar(250) NOT NULL,

    active_flag                 boolean NOT NULL DEFAULT TRUE,

    created_at                  timestamptz
                                NOT NULL
                                DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_merchant_source
        UNIQUE (
            source_system_code,
            source_merchant_key
        )
);


/*
===============================================================================
5. DIM_MERCHANT_LOCATION

Un mismo comercio puede operar desde múltiples ubicaciones.

La ubicación permanece como dimensión independiente del comercio para
permitir análisis por:
    - país
    - estado
    - ciudad
    - código postal
    - canal online/físico
===============================================================================
*/

CREATE TABLE olap.dim_merchant_location (
    merchant_location_key   integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    source_system_code      varchar(30) NOT NULL,
    source_location_key     varchar(150) NOT NULL,

    city                    varchar(150),
    region_code             varchar(100),
    postal_code             varchar(30),

    country_code            varchar(2) NOT NULL,

    online_flag             boolean NOT NULL DEFAULT FALSE,

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_merchant_location_source
        UNIQUE (
            source_system_code,
            source_location_key
        )
);


/*
===============================================================================
6. DIM_MERCHANT_CATEGORY
===============================================================================
*/

CREATE TABLE olap.dim_merchant_category (
    merchant_category_key   integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    category_scheme         varchar(30) NOT NULL,
    mcc_code                varchar(10) NOT NULL,

    category_name           varchar(200),
    category_description    varchar(500),

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_merchant_category
        UNIQUE (category_scheme, mcc_code)
);


/*
===============================================================================
7. DIM_AUTHORIZATION_STATUS
===============================================================================
*/

CREATE TABLE olap.dim_authorization_status (
    authorization_status_key
                            integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    status_code             varchar(40) NOT NULL,

    status_name             varchar(100) NOT NULL,

    status_description      varchar(250),

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_authorization_status_code
        UNIQUE (status_code)
);


/*
===============================================================================
8. DIM_DECLINE_REASON

Los registros que no sean DECLINED utilizarán posteriormente el miembro:

    NOT_APPLICABLE

De este modo fact_transaction no requiere una FK nula.
===============================================================================
*/

CREATE TABLE olap.dim_decline_reason (
    decline_reason_key      integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    reason_code             varchar(80) NOT NULL,

    reason_name             varchar(150) NOT NULL,

    reason_category         varchar(50) NOT NULL,

    reason_description      varchar(250),

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_decline_reason_code
        UNIQUE (reason_code)
);


/*
===============================================================================
9. DIM_ENTRY_MODE

Valores esperados:
    SWIPE
    CHIP
    ONLINE
    UNKNOWN
===============================================================================
*/

CREATE TABLE olap.dim_entry_mode (
    entry_mode_key          integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    entry_mode_code         varchar(50) NOT NULL,

    entry_mode_description  varchar(150),

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_entry_mode_code
        UNIQUE (entry_mode_code)
);


/*
===============================================================================
10. DIM_ERROR

Contiene el catálogo analítico de errores.

Una transacción puede tener varios errores en el OLTP.

En el OLAP se seleccionará únicamente el error principal según la prioridad
de ctl.source_error_mapping.

Transacciones sin error:
    NOT_APPLICABLE

Errores no reconocidos:
    UNKNOWN
===============================================================================
*/

CREATE TABLE olap.dim_error (
    error_key               integer
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    error_code              varchar(80) NOT NULL,

    error_description       varchar(250),

    active_flag             boolean NOT NULL DEFAULT TRUE,

    created_at              timestamptz
                            NOT NULL
                            DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_dim_error_code
        UNIQUE (error_code)
);


/*
===============================================================================
11. FACT_TRANSACTION

ÚNICA TABLA DE HECHOS DEL MODELO DIMENSIONAL.

Granularidad:
    Una fila por cada intento de transacción/autorización.

Volumen esperado:
    24,366,687 filas.

Medidas:
    amount
    transaction_count

Indicadores:
    international_flag
    declined_flag
    approved_flag
    reversed_flag
    error_flag
    fraud_flag

primary_error_key:
    Representa el error principal de la transacción.

    La selección se realizará de forma determinística según la prioridad
    definida en ctl.source_error_mapping.

    El detalle completo multivaluado permanece disponible en el OLTP.
===============================================================================
*/

CREATE TABLE olap.fact_transaction (
    transaction_fact_key        bigint
                                GENERATED ALWAYS AS IDENTITY
                                PRIMARY KEY,

    /*
    ---------------------------------------------------------------------------
    Trazabilidad operacional
    ---------------------------------------------------------------------------
    */

    oltp_transaction_id         bigint NOT NULL,

    source_system_code          varchar(30) NOT NULL,

    source_transaction_key      varchar(150) NOT NULL,


    /*
    ---------------------------------------------------------------------------
    Claves dimensionales
    ---------------------------------------------------------------------------
    */

    date_key                    integer NOT NULL,

    customer_key                integer NOT NULL,

    card_key                    integer NOT NULL,

    merchant_key                integer NOT NULL,

    merchant_location_key       integer NOT NULL,

    merchant_category_key       integer NOT NULL,

    authorization_status_key    integer NOT NULL,

    decline_reason_key          integer NOT NULL,

    entry_mode_key              integer NOT NULL,

    primary_error_key           integer NOT NULL,


    /*
    ---------------------------------------------------------------------------
    Atributos degenerados / temporales
    ---------------------------------------------------------------------------
    */

    transaction_datetime        timestamptz NOT NULL,

    transaction_hour            smallint NOT NULL,


    /*
    ---------------------------------------------------------------------------
    Medidas
    ---------------------------------------------------------------------------
    */

    amount                      numeric(18,2) NOT NULL,

    transaction_count           smallint
                                NOT NULL
                                DEFAULT 1,


    /*
    ---------------------------------------------------------------------------
    Indicadores analíticos
    ---------------------------------------------------------------------------
    */

    international_flag          boolean,

    declined_flag               boolean NOT NULL,

    approved_flag               boolean NOT NULL,

    reversed_flag               boolean NOT NULL,

    error_flag                  boolean NOT NULL,

    fraud_flag                  boolean NOT NULL,


    created_at                  timestamptz
                                NOT NULL
                                DEFAULT CURRENT_TIMESTAMP,


    /*
    ---------------------------------------------------------------------------
    Unicidad / reglas
    ---------------------------------------------------------------------------
    */

    CONSTRAINT uq_fact_transaction_oltp
        UNIQUE (oltp_transaction_id),

    CONSTRAINT uq_fact_transaction_source
        UNIQUE (
            source_system_code,
            source_transaction_key
        ),

    CONSTRAINT ck_fact_transaction_hour
        CHECK (
            transaction_hour BETWEEN 0 AND 23
        ),

    CONSTRAINT ck_fact_transaction_count
        CHECK (
            transaction_count = 1
        ),

    CONSTRAINT ck_fact_transaction_amount
        CHECK (
            amount <> 0
        ),


    /*
    ---------------------------------------------------------------------------
    Foreign Keys
    ---------------------------------------------------------------------------
    */

    CONSTRAINT fk_fact_transaction_date
        FOREIGN KEY (date_key)
        REFERENCES olap.dim_date(date_key),

    CONSTRAINT fk_fact_transaction_customer
        FOREIGN KEY (customer_key)
        REFERENCES olap.dim_customer(customer_key),

    CONSTRAINT fk_fact_transaction_card
        FOREIGN KEY (card_key)
        REFERENCES olap.dim_card(card_key),

    CONSTRAINT fk_fact_transaction_merchant
        FOREIGN KEY (merchant_key)
        REFERENCES olap.dim_merchant(merchant_key),

    CONSTRAINT fk_fact_transaction_location
        FOREIGN KEY (merchant_location_key)
        REFERENCES olap.dim_merchant_location(
            merchant_location_key
        ),

    CONSTRAINT fk_fact_transaction_category
        FOREIGN KEY (merchant_category_key)
        REFERENCES olap.dim_merchant_category(
            merchant_category_key
        ),

    CONSTRAINT fk_fact_transaction_status
        FOREIGN KEY (authorization_status_key)
        REFERENCES olap.dim_authorization_status(
            authorization_status_key
        ),

    CONSTRAINT fk_fact_transaction_decline_reason
        FOREIGN KEY (decline_reason_key)
        REFERENCES olap.dim_decline_reason(
            decline_reason_key
        ),

    CONSTRAINT fk_fact_transaction_entry_mode
        FOREIGN KEY (entry_mode_key)
        REFERENCES olap.dim_entry_mode(
            entry_mode_key
        ),

    CONSTRAINT fk_fact_transaction_primary_error
        FOREIGN KEY (primary_error_key)
        REFERENCES olap.dim_error(
            error_key
        )
);


/*
===============================================================================
Fin del modelo dimensional.

Resultado esperado:

    10 dimensiones

        dim_date
        dim_customer
        dim_card
        dim_merchant
        dim_merchant_location
        dim_merchant_category
        dim_authorization_status
        dim_decline_reason
        dim_entry_mode
        dim_error

    1 tabla de hechos

        fact_transaction

===============================================================================
*/