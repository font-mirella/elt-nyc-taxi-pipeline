-- staging_trips: renomeia para snake_case, padroniza tipos via TRY_CAST (LED-20/21) e
-- preserva os nulos do grupo payment_type=0 sem coalescer (LED-22, regra #6 de
-- docs/regras_limpeza.md). TRY_CAST é usado mesmo com o parquet já tipado corretamente
-- hoje: garante que uma execução futura com um mês malformado não quebre o pipeline.

CREATE OR REPLACE TABLE staging_trips AS
SELECT
    TRY_CAST(VendorID AS SMALLINT)              AS vendor_id,
    TRY_CAST(tpep_pickup_datetime AS TIMESTAMP) AS pickup_datetime,
    TRY_CAST(tpep_dropoff_datetime AS TIMESTAMP) AS dropoff_datetime,
    TRY_CAST(passenger_count AS TINYINT)        AS passenger_count,
    TRY_CAST(trip_distance AS DOUBLE)           AS trip_distance,
    TRY_CAST(RatecodeID AS SMALLINT)            AS ratecode_id,
    TRY_CAST(store_and_fwd_flag AS VARCHAR)     AS store_and_fwd_flag,
    TRY_CAST(PULocationID AS SMALLINT)          AS pu_location_id,
    TRY_CAST(DOLocationID AS SMALLINT)          AS do_location_id,
    TRY_CAST(payment_type AS SMALLINT)          AS payment_type,
    TRY_CAST(fare_amount AS DOUBLE)             AS fare_amount,
    TRY_CAST(extra AS DOUBLE)                   AS extra,
    TRY_CAST(mta_tax AS DOUBLE)                 AS mta_tax,
    TRY_CAST(tip_amount AS DOUBLE)              AS tip_amount,
    TRY_CAST(tolls_amount AS DOUBLE)            AS tolls_amount,
    TRY_CAST(improvement_surcharge AS DOUBLE)   AS improvement_surcharge,
    TRY_CAST(total_amount AS DOUBLE)            AS total_amount,
    TRY_CAST(congestion_surcharge AS DOUBLE)    AS congestion_surcharge,
    TRY_CAST(Airport_fee AS DOUBLE)             AS airport_fee,
    _loaded_at,
    _source_file
FROM raw_trips;
