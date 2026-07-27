-- dim_data (LED-28): dimensão de data. 1 linha por dia observado em pickup OU dropoff das
-- corridas aprovadas — role-playing (embarque/desembarque podem cair em dias diferentes,
-- inclusive fora de jan/2024 quando o dropoff cruza a virada do mês).
-- Chave inteligente AAAAMMDD (docs/modelagem_dimensional.md §2.2): legível em depuração,
-- ordenável, dispensa join para ser calculada a partir de um timestamp.
CREATE OR REPLACE TABLE dim_data AS
WITH datas AS (
    SELECT DISTINCT CAST(pickup_datetime AS DATE) AS data FROM approved_trips
    UNION
    SELECT DISTINCT CAST(dropoff_datetime AS DATE) FROM approved_trips
)
SELECT
    CAST(strftime(data, '%Y%m%d') AS INTEGER) AS id_data_sk,
    data AS data_completa,
    EXTRACT(YEAR FROM data) AS ano,
    EXTRACT(MONTH FROM data) AS mes,
    EXTRACT(DAY FROM data) AS dia,
    DAYOFWEEK(data) AS dia_semana_num,
    CASE DAYOFWEEK(data)
        WHEN 1 THEN 'Domingo' WHEN 2 THEN 'Segunda' WHEN 3 THEN 'Terça'
        WHEN 4 THEN 'Quarta'  WHEN 5 THEN 'Quinta'  WHEN 6 THEN 'Sexta'
        WHEN 7 THEN 'Sábado'
    END AS dia_semana_nome,
    DAYOFWEEK(data) IN (1, 7) AS fim_de_semana
FROM datas
ORDER BY data;
