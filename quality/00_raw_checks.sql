SELECT 'raw_trips' AS tabela, count(*) AS linhas FROM raw_trips
UNION ALL
SELECT 'raw_zone_lookup', count(*) FROM raw_zone_lookup;

DESCRIBE raw_trips;
DESCRIBE raw_zone_lookup;
