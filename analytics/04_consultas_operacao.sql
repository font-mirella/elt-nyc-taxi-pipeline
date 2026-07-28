-- Consultas de Operação (LED-39): distância, velocidade aproximada, ocupação e viagens fora
-- do padrão. Consulta apenas o modelo final (fato_corrida + dim_hora), nunca staging/raw
-- diretamente (mesma exigência de LED-36/LED-37).
--
-- Velocidade aproximada = trip_distance / (trip_duration_minutes / 60), calculada em consulta
-- (não materializada na fato). is_speed_outlier/is_distance_outlier (regras_limpeza.md itens
-- 4-5) marcam corridas curtas com erro de GPS/taxímetro (velocidade implícita > 50mph) — as
-- consultas de velocidade/eficiência (2, 3) excluem essas linhas por padrão, já que sem isso
-- a média fica dominada pelo artefato de captura, não pelo trânsito real; as demais mantêm
-- todas as linhas, e a consulta 5 isola os outliers para comparação.

-- 1. Distribuição da distância das corridas em faixas
SELECT
    CASE
        WHEN trip_distance = 0    THEN '0: 0 mi'
        WHEN trip_distance < 1    THEN '1: < 1 mi'
        WHEN trip_distance < 3    THEN '2: 1-3 mi'
        WHEN trip_distance < 6    THEN '3: 3-6 mi'
        WHEN trip_distance < 12   THEN '4: 6-12 mi'
        ELSE '5: 12+ mi'
    END AS faixa_distancia,
    COUNT(*) AS qtd_corridas
FROM fato_corrida
GROUP BY faixa_distancia
ORDER BY faixa_distancia;

-- 2. Velocidade média implícita por turno, excluindo is_speed_outlier e linhas sem distância/
-- duração válida para a razão
SELECT
    h.turno,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.trip_distance / (f.trip_duration_minutes / 60.0)), 1) AS velocidade_media_mph
FROM fato_corrida f
JOIN dim_hora h ON h.id_hora_sk = f.id_hora_embarque_sk
WHERE f.trip_distance > 0 AND f.trip_duration_minutes > 0 AND NOT f.is_speed_outlier
GROUP BY h.turno
ORDER BY velocidade_media_mph DESC;

-- 3. Eficiência por faixa de distância: duração e velocidade média implícita (mesmos filtros
-- da consulta 2)
SELECT
    CASE
        WHEN trip_distance < 1  THEN '1: < 1 mi'
        WHEN trip_distance < 3  THEN '2: 1-3 mi'
        WHEN trip_distance < 6  THEN '3: 3-6 mi'
        WHEN trip_distance < 12 THEN '4: 6-12 mi'
        ELSE '5: 12+ mi'
    END AS faixa_distancia,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(trip_duration_minutes), 1) AS duracao_media_min,
    ROUND(AVG(trip_distance / (trip_duration_minutes / 60.0)), 1) AS velocidade_media_mph
FROM fato_corrida
WHERE trip_distance > 0 AND trip_duration_minutes > 0 AND NOT is_speed_outlier
GROUP BY faixa_distancia
ORDER BY faixa_distancia;

-- 4. Ocupação: distribuição de corridas e distância média por número de passageiros
SELECT
    passenger_count,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(trip_distance), 2) AS distancia_media_mi
FROM fato_corrida
WHERE passenger_count IS NOT NULL
GROUP BY passenger_count
ORDER BY passenger_count;

-- 5. Viagens fora do padrão: volume e participação de is_distance_outlier (regras_limpeza.md
-- item 4) e is_speed_outlier (item 5)
SELECT
    SUM(CASE WHEN is_distance_outlier THEN 1 ELSE 0 END) AS qtd_distance_outlier,
    SUM(CASE WHEN is_speed_outlier THEN 1 ELSE 0 END) AS qtd_speed_outlier,
    COUNT(*) AS total_corridas,
    ROUND(100.0 * SUM(CASE WHEN is_distance_outlier THEN 1 ELSE 0 END) / COUNT(*), 3) AS pct_distance_outlier,
    ROUND(100.0 * SUM(CASE WHEN is_speed_outlier THEN 1 ELSE 0 END) / COUNT(*), 3) AS pct_speed_outlier
FROM fato_corrida;

-- 6. Assinatura dos outliers de velocidade: distância e duração médias comparadas com as
-- corridas normais (mesma causa-raiz documentada em regras_limpeza.md item 5 — corrida curta
-- com erro de captura, não velocidade real)
SELECT
    is_speed_outlier,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(trip_distance), 2) AS distancia_media_mi,
    ROUND(AVG(trip_duration_minutes), 2) AS duracao_media_min
FROM fato_corrida
WHERE trip_distance > 0 AND trip_duration_minutes > 0
GROUP BY is_speed_outlier;
