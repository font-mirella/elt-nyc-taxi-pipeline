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
    -- DAYOFWEEK no DuckDB é 0-indexado com domingo=0 (validado: DAYOFWEEK('2024-01-01') = 1,
    -- e 2024-01-01 é segunda-feira) - não confundir com a convenção 1=domingo/7=sábado.
    DAYOFWEEK(data) AS dia_semana_num,
    CASE DAYOFWEEK(data)
        WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'
        WHEN 3 THEN 'Quarta'  WHEN 4 THEN 'Quinta'  WHEN 5 THEN 'Sexta'
        WHEN 6 THEN 'Sábado'
    END AS dia_semana_nome,
    DAYOFWEEK(data) IN (0, 6) AS fim_de_semana
FROM datas
ORDER BY data;
