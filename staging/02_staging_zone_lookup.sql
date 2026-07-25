-- staging_zone_lookup: renomeia para snake_case e normaliza 'N/A'/'Unknown' (texto
-- literal na fonte, não NULL — achado §8.9 de docs/hipotese_grao.md) para uma única
-- categoria "Desconhecido" (LED-20, regra #9 de docs/regras_limpeza.md).

CREATE OR REPLACE TABLE staging_zone_lookup AS
SELECT
    TRY_CAST(LocationID AS SMALLINT) AS location_id,
    CASE WHEN Borough IN ('N/A', 'Unknown') THEN 'Desconhecido' ELSE Borough END AS borough,
    CASE WHEN Zone IN ('N/A', 'Unknown') THEN 'Desconhecido' ELSE Zone END AS zone,
    CASE WHEN service_zone IN ('N/A', 'Unknown') THEN 'Desconhecido' ELSE service_zone END AS service_zone
FROM raw_zone_lookup;
