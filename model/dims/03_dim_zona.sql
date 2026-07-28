-- dim_zona (LED-29): dimensão de localização com role-playing (origem/destino da corrida
-- reutilizam a mesma tabela). Chave substituta id_zona_sk isolada da fonte por convenção
-- do modelo (docs/modelagem_dimensional.md §2.3) — location_id fica como atributo natural
-- para lookup, não como chave.
-- 'Desconhecido' em borough/zone/service_zone já vem normalizado de staging_zone_lookup
-- (regras_limpeza.md item 9); por isso esta dimensão não precisa de valor reservado próprio
-- (exceção registrada em docs/modelagem_dimensional.md §2.4).
CREATE OR REPLACE TABLE dim_zona AS
SELECT
    ROW_NUMBER() OVER (ORDER BY location_id) AS id_zona_sk,
    location_id,
    borough,
    zone,
    service_zone
FROM staging_zone_lookup
ORDER BY location_id;
