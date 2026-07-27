-- Verificações de qualidade da camada de staging (LED-22): duplicidade e códigos
-- sem correspondência. error() interrompe run_all.sql se uma invariante quebrar —
-- deixa de ser silencioso caso um mês futuro traga dado diferente do perfilado.

-- Duplicidade: perfilamento (docs/perfilamento_notas.md) encontrou 0 em raw_trips;
-- deve continuar 0 depois do TRY_CAST em staging_trips.
SELECT CASE
    WHEN (
        SELECT count(*) FROM (
            SELECT vendor_id, pickup_datetime, dropoff_datetime, passenger_count, trip_distance,
                   ratecode_id, store_and_fwd_flag, pu_location_id, do_location_id, payment_type,
                   fare_amount, extra, mta_tax, tip_amount, tolls_amount, improvement_surcharge,
                   total_amount, congestion_surcharge, airport_fee
            FROM staging_trips
            GROUP BY ALL
            HAVING count(*) > 1
        ) dups
    ) > 0
    THEN error('staging_trips: duplicidade encontrada - revisar regra de dedupe em docs/regras_limpeza.md')
    ELSE 'ok: nenhuma duplicidade'
END AS check_duplicidade;

-- Códigos de zona sem correspondência: perfilamento encontrou 0 em jan/2024.
SELECT CASE
    WHEN (
        SELECT count(*) FROM staging_trips t
        LEFT JOIN staging_zone_lookup z ON t.pu_location_id = z.location_id
        WHERE z.location_id IS NULL
    ) > 0
    THEN error('staging_trips: PULocationID sem correspondencia em staging_zone_lookup')
    ELSE 'ok: pu_location_id 100% coberto'
END AS check_pu_location;

SELECT CASE
    WHEN (
        SELECT count(*) FROM staging_trips t
        LEFT JOIN staging_zone_lookup z ON t.do_location_id = z.location_id
        WHERE z.location_id IS NULL
    ) > 0
    THEN error('staging_trips: DOLocationID sem correspondencia em staging_zone_lookup')
    ELSE 'ok: do_location_id 100% coberto'
END AS check_do_location;

-- Domínio dos códigos categóricos: fora do domínio validado no perfilamento não é
-- erro automático (regra #3 de docs/regras_limpeza.md) — só sinaliza, não falha.
SELECT
    count(*) FILTER (WHERE vendor_id NOT IN (1, 2, 6))                                     AS vendor_id_fora_do_dominio,
    count(*) FILTER (WHERE ratecode_id IS NOT NULL AND ratecode_id NOT IN (1,2,3,4,5,6,99)) AS ratecode_id_fora_do_dominio,
    count(*) FILTER (WHERE payment_type NOT IN (0,1,2,3,4,5,6))                             AS payment_type_fora_do_dominio
FROM staging_trips;
