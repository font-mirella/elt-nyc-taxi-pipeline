-- Consultas de Tempo (LED-36): variação por dia da semana, hora, período do dia e duração
-- das viagens. Consulta apenas o modelo final (fato_corrida + dim_data + dim_hora), nunca
-- staging/raw diretamente (exigência da própria task).
--
-- As flags is_speed_outlier/is_distance_outlier existem em fato_corrida para quem quiser
-- excluir viagens de duração/distância anômala destas médias (não filtradas aqui por padrão -
-- regras_limpeza.md decide manter a linha, o consumo analítico decide incluir ou não).

-- 1. Volume e duração média por dia da semana (role-playing: usa a data de embarque)
SELECT
    d.dia_semana_nome,
    d.fim_de_semana,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.trip_duration_minutes), 2) AS duracao_media_min,
    ROUND(AVG(f.trip_distance), 2) AS distancia_media_mi
FROM fato_corrida f
JOIN dim_data d ON d.id_data_sk = f.id_data_embarque_sk
GROUP BY d.dia_semana_nome, d.fim_de_semana, d.dia_semana_num
ORDER BY d.dia_semana_num;

-- 2. Volume e duração média por hora do dia, com turno e faixa de pico (percentil 75 de
-- volume, ver model/dims/02_dim_hora.sql)
SELECT
    h.id_hora_sk AS hora,
    h.turno,
    h.faixa_pico,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.trip_duration_minutes), 2) AS duracao_media_min
FROM fato_corrida f
JOIN dim_hora h ON h.id_hora_sk = f.id_hora_embarque_sk
GROUP BY h.id_hora_sk, h.turno, h.faixa_pico
ORDER BY h.id_hora_sk;

-- 3. Agregado por turno (Madrugada/Manhã/Tarde/Noite)
SELECT
    h.turno,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.trip_duration_minutes), 2) AS duracao_media_min,
    ROUND(AVG(f.trip_distance), 2) AS distancia_media_mi
FROM fato_corrida f
JOIN dim_hora h ON h.id_hora_sk = f.id_hora_embarque_sk
GROUP BY h.turno
ORDER BY qtd_corridas DESC;

-- 4. Pico vs. fora de pico
SELECT
    h.faixa_pico,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.trip_duration_minutes), 2) AS duracao_media_min
FROM fato_corrida f
JOIN dim_hora h ON h.id_hora_sk = f.id_hora_embarque_sk
GROUP BY h.faixa_pico;

-- 5. Distribuição da duração das viagens em faixas
SELECT
    CASE
        WHEN trip_duration_minutes < 5  THEN '1: < 5 min'
        WHEN trip_duration_minutes < 15 THEN '2: 5-15 min'
        WHEN trip_duration_minutes < 30 THEN '3: 15-30 min'
        WHEN trip_duration_minutes < 60 THEN '4: 30-60 min'
        ELSE '5: 60+ min'
    END AS faixa_duracao,
    COUNT(*) AS qtd_corridas
FROM fato_corrida
GROUP BY faixa_duracao
ORDER BY faixa_duracao;
