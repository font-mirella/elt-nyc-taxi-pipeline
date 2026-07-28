-- Consultas Financeiras (LED-38): composição do valor, gorjetas, pedágios, tarifas e formas
-- de pagamento. Consulta apenas o modelo final (fato_corrida + dim_pagamento), nunca
-- staging/raw diretamente (mesma exigência de LED-36/LED-37).
--
-- is_estorno/is_tip_outlier/is_fare_outlier existem em fato_corrida para quem quiser excluir
-- linhas atípicas destas médias (não filtradas por padrão nas consultas 1-5 — regras_limpeza.md
-- decide manter a linha, o consumo analítico decide incluir ou não; as consultas 6-7 abaixo
-- isolam exatamente essas linhas).

-- 1. Composição média do valor: média de cada componente e sua participação percentual no
-- total_amount (SUM/SUM, não AVG das razões individuais, para não distorcer com corridas de
-- valor baixo). congestion_surcharge/airport_fee usam AVG(COALESCE(..., 0)): NULL nessas duas
-- colunas é ausência estrutural do grupo Flex Fare (regras_limpeza.md item 6), não "sem
-- informação" - AVG puro pula o NULL e divide por um denominador menor que o das outras
-- colunas (que não têm NULL), inflando a média e quebrando a comparação entre componentes.
-- A própria fato trata esse NULL como contribuição zero no total_amount (item 10), então
-- COALESCE a 0 aqui só torna a média consistente com o dado já materializado.
SELECT
    ROUND(AVG(fare_amount), 2) AS fare_medio,
    ROUND(AVG(extra), 2) AS extra_medio,
    ROUND(AVG(mta_tax), 2) AS mta_tax_medio,
    ROUND(AVG(tip_amount), 2) AS gorjeta_media,
    ROUND(AVG(tolls_amount), 2) AS pedagio_medio,
    ROUND(AVG(improvement_surcharge), 2) AS improvement_medio,
    ROUND(AVG(COALESCE(congestion_surcharge, 0)), 2) AS congestion_medio,
    ROUND(AVG(COALESCE(airport_fee, 0)), 2) AS airport_fee_medio,
    ROUND(AVG(total_amount), 2) AS total_medio,
    ROUND(100 * SUM(fare_amount) / SUM(total_amount), 1) AS pct_fare,
    ROUND(100 * SUM(extra) / SUM(total_amount), 1) AS pct_extra,
    ROUND(100 * SUM(mta_tax) / SUM(total_amount), 1) AS pct_mta_tax,
    ROUND(100 * SUM(tip_amount) / SUM(total_amount), 1) AS pct_gorjeta,
    ROUND(100 * SUM(tolls_amount) / SUM(total_amount), 1) AS pct_pedagio,
    ROUND(100 * SUM(improvement_surcharge) / SUM(total_amount), 1) AS pct_improvement,
    ROUND(100 * SUM(COALESCE(congestion_surcharge, 0)) / SUM(total_amount), 1) AS pct_congestion,
    ROUND(100 * SUM(COALESCE(airport_fee, 0)) / SUM(total_amount), 1) AS pct_airport_fee
FROM fato_corrida
WHERE total_amount > 0;

-- 2. Volume, valor arrecadado e ticket médio por forma de pagamento
SELECT
    p.payment_type_desc,
    COUNT(*) AS qtd_corridas,
    ROUND(SUM(f.total_amount), 2) AS valor_total,
    ROUND(AVG(f.total_amount), 2) AS ticket_medio
FROM fato_corrida f
JOIN dim_pagamento p ON p.id_pagamento_sk = f.id_pagamento_sk
GROUP BY p.payment_type_desc
ORDER BY qtd_corridas DESC;

-- 3. Gorjeta média e % de gorjeta sobre a tarifa, por forma de pagamento (só onde fare_amount
-- > 0, para a razão gorjeta/tarifa fazer sentido). % é SUM/SUM, não AVG da razão por linha
-- (docs/modelagem_dimensional.md §3.5) - média de razões infla o resultado puxada pelas
-- corridas de tarifa baixa, onde qualquer gorjeta vira um percentual desproporcional.
SELECT
    p.payment_type_desc,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.tip_amount), 2) AS gorjeta_media,
    ROUND(100 * SUM(f.tip_amount) / SUM(f.fare_amount), 1) AS pct_gorjeta_media
FROM fato_corrida f
JOIN dim_pagamento p ON p.id_pagamento_sk = f.id_pagamento_sk
WHERE f.fare_amount > 0
GROUP BY p.payment_type_desc
ORDER BY gorjeta_media DESC;

-- 4. Corridas com pedágio vs. sem pedágio: volume, participação e ticket médio
SELECT
    CASE WHEN tolls_amount > 0 THEN 'Com pedágio' ELSE 'Sem pedágio' END AS grupo,
    COUNT(*) AS qtd_corridas,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_corridas,
    ROUND(AVG(total_amount), 2) AS ticket_medio,
    ROUND(AVG(trip_distance), 2) AS distancia_media_mi
FROM fato_corrida
GROUP BY grupo;

-- 5. Distribuição das tarifas (fare_amount) em faixas, com ticket médio (total_amount) por
-- faixa
SELECT
    CASE
        WHEN fare_amount < 10 THEN '1: < $10'
        WHEN fare_amount < 20 THEN '2: $10-20'
        WHEN fare_amount < 40 THEN '3: $20-40'
        WHEN fare_amount < 70 THEN '4: $40-70'
        ELSE '5: $70+'
    END AS faixa_tarifa,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(total_amount), 2) AS ticket_medio
FROM fato_corrida
WHERE fare_amount >= 0
GROUP BY faixa_tarifa
ORDER BY faixa_tarifa;

-- 6. Estornos (is_estorno, regras_limpeza.md item 2): volume e tarifa média por forma de
-- pagamento — confirma a concentração em No charge/Dispute
SELECT
    p.payment_type_desc,
    COUNT(*) AS qtd_corridas,
    ROUND(AVG(f.fare_amount), 2) AS fare_medio
FROM fato_corrida f
JOIN dim_pagamento p ON p.id_pagamento_sk = f.id_pagamento_sk
WHERE f.is_estorno
GROUP BY p.payment_type_desc
ORDER BY qtd_corridas DESC;

-- 7. Viagens com valor fora do padrão: volume e participação de is_fare_outlier (teto de
-- sistema, regras_limpeza.md item 11) e is_tip_outlier (gorjeta atípica, item 7)
SELECT
    SUM(CASE WHEN is_fare_outlier THEN 1 ELSE 0 END) AS qtd_fare_outlier,
    SUM(CASE WHEN is_tip_outlier THEN 1 ELSE 0 END) AS qtd_tip_outlier,
    COUNT(*) AS total_corridas,
    ROUND(100.0 * SUM(CASE WHEN is_fare_outlier THEN 1 ELSE 0 END) / COUNT(*), 3) AS pct_fare_outlier,
    ROUND(100.0 * SUM(CASE WHEN is_tip_outlier THEN 1 ELSE 0 END) / COUNT(*), 3) AS pct_tip_outlier
FROM fato_corrida;
