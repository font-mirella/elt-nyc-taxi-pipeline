-- fato_corrida (LED-27): tabela fato de corridas de táxi.
-- Grão: 1 linha = 1 corrida aprovada no staging (docs/modelagem_dimensional.md §1).
-- Fonte: approved_trips + as dimensões construídas nesta etapa (model/dims/*).
CREATE OR REPLACE TABLE fato_corrida AS
SELECT
    -- Surrogate key determinística: md5 das 19 colunas de negócio (docs/modelagem_dimensional.md
    -- §2.1). Duas execuções do pipeline sobre a mesma fonte produzem sempre a mesma chave —
    -- é isso que torna o pipeline idempotente. '¤' distingue NULL de string vazia na concatenação.
    md5(
        COALESCE(CAST(a.vendor_id AS VARCHAR), '¤') || '|' ||
        CAST(a.pickup_datetime AS VARCHAR) || '|' ||
        CAST(a.dropoff_datetime AS VARCHAR) || '|' ||
        COALESCE(CAST(a.passenger_count AS VARCHAR), '¤') || '|' ||
        CAST(a.trip_distance AS VARCHAR) || '|' ||
        COALESCE(CAST(a.ratecode_id AS VARCHAR), '¤') || '|' ||
        COALESCE(a.store_and_fwd_flag, '¤') || '|' ||
        CAST(a.pu_location_id AS VARCHAR) || '|' ||
        CAST(a.do_location_id AS VARCHAR) || '|' ||
        CAST(a.payment_type AS VARCHAR) || '|' ||
        CAST(a.fare_amount AS VARCHAR) || '|' ||
        CAST(a.extra AS VARCHAR) || '|' ||
        CAST(a.mta_tax AS VARCHAR) || '|' ||
        CAST(a.tip_amount AS VARCHAR) || '|' ||
        CAST(a.tolls_amount AS VARCHAR) || '|' ||
        CAST(a.improvement_surcharge AS VARCHAR) || '|' ||
        CAST(a.total_amount AS VARCHAR) || '|' ||
        COALESCE(CAST(a.congestion_surcharge AS VARCHAR), '¤') || '|' ||
        COALESCE(CAST(a.airport_fee AS VARCHAR), '¤')
    ) AS id_corrida_sk,

    -- FKs temporais, role-playing embarque/desembarque (docs/modelagem_dimensional.md §4.1).
    -- Chaves inteligentes calculadas direto do timestamp, sem join: dim_data/dim_hora
    -- garantem cobertura de todo o intervalo observado em pickup/dropoff.
    CAST(strftime(CAST(a.pickup_datetime AS DATE), '%Y%m%d') AS INTEGER) AS id_data_embarque_sk,
    a.pickup_hour AS id_hora_embarque_sk,
    CAST(strftime(CAST(a.dropoff_datetime AS DATE), '%Y%m%d') AS INTEGER) AS id_data_desembarque_sk,
    EXTRACT(HOUR FROM a.dropoff_datetime) AS id_hora_desembarque_sk,

    -- FKs de zona, role-playing PU/DO
    z_pu.id_zona_sk AS id_zona_pu_sk,
    z_do.id_zona_sk AS id_zona_do_sk,

    -- FK de pagamento (smart key: coincide com payment_type, ver dim_pagamento)
    a.payment_type AS id_pagamento_sk,

    -- FK da junk dimension
    ja.id_atributos_sk,

    -- Degenerados (docs/modelagem_dimensional.md §3.2): precisão de segundo que dim_data/
    -- dim_hora não carregam (grão de dia/hora)
    a.pickup_datetime,
    a.dropoff_datetime,

    -- Medidas aditivas
    a.passenger_count,
    a.trip_distance,
    a.fare_amount,
    a.extra,
    a.mta_tax,
    a.tip_amount,
    a.tolls_amount,
    a.improvement_surcharge,
    a.congestion_surcharge,
    a.airport_fee,
    a.total_amount,
    a.trip_duration_minutes,

    -- Flags de qualidade materializadas (docs/modelagem_dimensional.md §3.4). is_speed_outlier
    -- entra também: regras_limpeza.md item 5 pede a flag na fato, mesmo a tabela-síntese de
    -- atributos do modelo (§4.3) não listando-a explicitamente — tratado aqui como omissão do
    -- doc de modelagem, não como decisão de excluir.
    a.is_estorno,
    a.is_distance_outlier,
    a.is_speed_outlier,
    a.is_tip_outlier,
    a.is_fare_outlier,
    a.is_aeroporto
FROM approved_trips a
JOIN dim_zona z_pu ON z_pu.location_id = a.pu_location_id
JOIN dim_zona z_do ON z_do.location_id = a.do_location_id
JOIN dim_atributos_corrida ja
    ON ja.vendor_id = a.vendor_id
    AND ja.ratecode_id = COALESCE(a.ratecode_id, -1)                       
    AND ja.store_and_fwd_flag = COALESCE(a.store_and_fwd_flag, 'N/A');
