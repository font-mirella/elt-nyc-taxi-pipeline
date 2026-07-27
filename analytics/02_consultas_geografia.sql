-- Consultas de Geografia (LED-37): fluxos entre zonas, origem/destino mais frequentes em
-- diferentes granularidades (zona e borough). Consulta apenas o modelo final (fato_corrida +
-- dim_zona, role-playing PU/DO), nunca staging/raw diretamente.

-- 1. Top 10 pares de zona origem -> destino mais frequentes
SELECT
    z_pu.zone AS zona_origem,
    z_do.zone AS zona_destino,
    COUNT(*) AS qtd_corridas
FROM fato_corrida f
JOIN dim_zona z_pu ON z_pu.id_zona_sk = f.id_zona_pu_sk
JOIN dim_zona z_do ON z_do.id_zona_sk = f.id_zona_do_sk
GROUP BY z_pu.zone, z_do.zone
ORDER BY qtd_corridas DESC
LIMIT 10;

-- 2. Top 5 zonas de origem
SELECT
    z.zone,
    z.borough,
    COUNT(*) AS qtd_corridas
FROM fato_corrida f
JOIN dim_zona z ON z.id_zona_sk = f.id_zona_pu_sk
GROUP BY z.zone, z.borough
ORDER BY qtd_corridas DESC
LIMIT 5;

-- 3. Top 5 zonas de destino
SELECT
    z.zone,
    z.borough,
    COUNT(*) AS qtd_corridas
FROM fato_corrida f
JOIN dim_zona z ON z.id_zona_sk = f.id_zona_do_sk
GROUP BY z.zone, z.borough
ORDER BY qtd_corridas DESC
LIMIT 5;

-- 4. Fluxo entre boroughs (origem x destino) - granularidade mais alta
SELECT
    z_pu.borough AS borough_origem,
    z_do.borough AS borough_destino,
    COUNT(*) AS qtd_corridas
FROM fato_corrida f
JOIN dim_zona z_pu ON z_pu.id_zona_sk = f.id_zona_pu_sk
JOIN dim_zona z_do ON z_do.id_zona_sk = f.id_zona_do_sk
GROUP BY z_pu.borough, z_do.borough
ORDER BY qtd_corridas DESC;

-- 5. Top 3 zonas de destino para cada borough de origem
WITH ranked AS (
    SELECT
        z_pu.borough AS borough_origem,
        z_do.zone AS zona_destino,
        COUNT(*) AS qtd_corridas,
        ROW_NUMBER() OVER (PARTITION BY z_pu.borough ORDER BY COUNT(*) DESC) AS posicao
    FROM fato_corrida f
    JOIN dim_zona z_pu ON z_pu.id_zona_sk = f.id_zona_pu_sk
    JOIN dim_zona z_do ON z_do.id_zona_sk = f.id_zona_do_sk
    GROUP BY z_pu.borough, z_do.zone
)
SELECT borough_origem, zona_destino, qtd_corridas
FROM ranked
WHERE posicao <= 3
ORDER BY borough_origem, posicao;

-- 6. Top 10 zonas de origem de corridas de aeroporto (is_aeroporto, regras_limpeza.md item 8)
SELECT
    z.zone,
    z.borough,
    COUNT(*) AS qtd_corridas
FROM fato_corrida f
JOIN dim_zona z ON z.id_zona_sk = f.id_zona_pu_sk
WHERE f.is_aeroporto
GROUP BY z.zone, z.borough
ORDER BY qtd_corridas DESC
LIMIT 10;
