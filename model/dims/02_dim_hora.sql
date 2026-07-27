-- dim_hora (LED-28): dimensão de hora do dia. Domínio fechado 0-23, chave substituta
-- coincide com o valor natural (docs/modelagem_dimensional.md §2.2). Materializada via
-- range() e não por DISTINCT sobre a fato: garante as 24 horas mesmo que alguma não
-- apareça num mês futuro de dados.
--
-- faixa_pico é derivada por evidência (percentil 75 do volume de corridas por hora em
-- approved_trips), não por suposição de horário de rush — mesmo princípio de
-- docs/regras_limpeza.md ("regra nasce do perfilamento, não de intuição").
CREATE OR REPLACE TABLE dim_hora AS
WITH horas AS (
    SELECT UNNEST(range(0, 24)) AS id_hora_sk
),
volume_por_hora AS (
    SELECT pickup_hour, COUNT(*) AS qtd FROM approved_trips GROUP BY pickup_hour
),
limiar AS (
    SELECT QUANTILE_CONT(qtd, 0.75) AS p75 FROM volume_por_hora
)
SELECT
    h.id_hora_sk,
    CASE
        WHEN h.id_hora_sk BETWEEN 6 AND 11 THEN 'Manhã'
        WHEN h.id_hora_sk BETWEEN 12 AND 17 THEN 'Tarde'
        WHEN h.id_hora_sk BETWEEN 18 AND 23 THEN 'Noite'
        ELSE 'Madrugada'
    END AS turno,
    COALESCE(v.qtd, 0) >= (SELECT p75 FROM limiar) AS faixa_pico
FROM horas h
LEFT JOIN volume_por_hora v ON v.pickup_hour = h.id_hora_sk
ORDER BY h.id_hora_sk;
