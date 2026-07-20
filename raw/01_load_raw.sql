CREATE OR REPLACE TABLE raw_trips AS
SELECT *, current_timestamp AS _loaded_at, 'yellow_tripdata_2024-01.parquet' AS _source_file
FROM read_parquet('raw/data/yellow_tripdata_2024-01.parquet');

CREATE OR REPLACE TABLE raw_zone_lookup AS
SELECT *, current_timestamp AS _loaded_at, 'taxi_zone_lookup.csv' AS _source_file
FROM read_csv('raw/data/taxi_zone_lookup.csv', header=true, auto_detect=true);
