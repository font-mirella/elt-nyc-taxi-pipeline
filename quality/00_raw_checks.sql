-- =====================================================================
-- Consultas de verificação de qualidade (auditoria da camada raw)
-- Fonte: raw_trips (2.964.624 linhas) + raw_zone_lookup (265 linhas)
-- =====================================================================

-- VOLUME, TIPOS E NULIDADE GERAL  

SELECT 'raw_trips' AS tabela, count(*) AS linhas FROM raw_trips
UNION ALL
SELECT 'raw_zone_lookup', count(*) FROM raw_zone_lookup;

DESCRIBE raw_trips;
DESCRIBE raw_zone_lookup;

-- Nulidade de todas as colunas de uma vez. Só 5 colunas têm nulo (4,73%).
SELECT column_name, null_percentage
FROM (SUMMARIZE raw_trips);

-- VendorID  

-- Domínio: 1, 2, 6. Código 7 (Helix) do dicionário não aparece em jan/2024.
SELECT VendorID, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY VendorID
ORDER BY corridas_associadas DESC;


-- DUPLICIDADE DE LINHA 

-- Todas as 19 colunas de negócio: 2.964.624 = 2.964.624 -> ZERO duplicatas.
WITH distintas AS (
  SELECT DISTINCT VendorID, tpep_pickup_datetime, tpep_dropoff_datetime, passenger_count,
         trip_distance, RatecodeID, store_and_fwd_flag, PULocationID, DOLocationID,
         payment_type, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
         improvement_surcharge, total_amount, congestion_surcharge, Airport_fee
  FROM raw_trips
)
SELECT (SELECT COUNT(*) FROM raw_trips)  AS total_linhas,
       (SELECT COUNT(*) FROM distintas)  AS linhas_distintas,
       (SELECT COUNT(*) FROM raw_trips) - (SELECT COUNT(*) FROM distintas) AS duplicatas;

-- tpep_pickup_datetime / tpep_dropoff_datetime  

-- Intervalo: registro mais antigo em 2002 (incompatível com jan/2024).
SELECT MIN(tpep_pickup_datetime) AS primeira_partida, MAX(tpep_pickup_datetime) AS ultima_partida,
       MIN(tpep_dropoff_datetime) AS primeira_chegada, MAX(tpep_dropoff_datetime) AS ultima_chegada
FROM raw_trips;

-- 15 corridas fora de jan/2024.
SELECT COUNT(*) AS total_fora_de_2024
FROM raw_trips
WHERE tpep_pickup_datetime < '2024-01-01' OR tpep_pickup_datetime >= '2025-01-01';

-- 56 corridas com dropoff antes do pickup (fisicamente impossível).
SELECT COUNT(*) AS viagens_invertidas
FROM raw_trips
WHERE tpep_dropoff_datetime < tpep_pickup_datetime;

-- passenger_count  

-- Domínio: 0-9 + NULL.
SELECT DISTINCT passenger_count FROM raw_trips ORDER BY passenger_count;

-- passenger_count = 0 concentrado no VendorID 1 (4,3%). Não filtrar > 4.
SELECT VendorID, COUNT(*) AS total_viagens,
       SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) AS viagens_com_zero_pass,
       ROUND(SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct
FROM raw_trips
GROUP BY VendorID;

-- trip_distance 

-- Distribuição da distância pura: 99,9% <= 33,52 mi; salto no P99,99 = erro.
SELECT APPROX_QUANTILE(trip_distance, 0.9)  AS p90,
       APPROX_QUANTILE(trip_distance, 0.99) AS p99,
       APPROX_QUANTILE(trip_distance, 0.999)  AS p999,
       APPROX_QUANTILE(trip_distance, 0.9999) AS p9999
FROM raw_trips;

-- Limiar de "distância improvável": >50 mi OU razão dist/fare > 5.  Resultado: 819 (0,03%).
SELECT COUNT(*) FILTER (WHERE trip_distance > 50) AS dist_maior_50,
       COUNT(*) FILTER (WHERE fare_amount > 0 AND trip_distance/fare_amount > 5) AS razao_maior_5,
       COUNT(*) FILTER (WHERE trip_distance > 50 OR (fare_amount > 0 AND trip_distance/fare_amount > 5)) AS total_improvavel
FROM raw_trips;

-- Distância zero por RatecodeID: alta em 5/6 (esperado); anômala só em RatecodeID 1.
WITH totais AS (SELECT RatecodeID, COUNT(*) AS total FROM raw_trips GROUP BY RatecodeID),
     zeros  AS (SELECT RatecodeID, COUNT(*) AS qtd_zero FROM raw_trips WHERE trip_distance = 0 GROUP BY RatecodeID)
SELECT z.RatecodeID, z.qtd_zero, t.total, ROUND(z.qtd_zero * 100.0 / t.total, 2) AS pct_zero
FROM zeros z JOIN totais t ON z.RatecodeID IS NOT DISTINCT FROM t.RatecodeID
ORDER BY pct_zero DESC;

-- RatecodeID  (LED-15)

-- Domínio bate com o dicionário; 99 = Null/unknown é categoria válida.
SELECT COALESCE(CAST(RatecodeID AS VARCHAR), 'NULO') AS RatecodeID, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY RatecodeID
ORDER BY RatecodeID;

-- store_and_fwd_flag  

-- Domínio: N (~95%), Y (~0,4%), NULO.
SELECT COALESCE(store_and_fwd_flag, 'NULO') AS store_and_fwd_flag, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY store_and_fwd_flag
ORDER BY store_and_fwd_flag;

-- PULocationID / DOLocationID + integridade referencial 

-- Zonas que existem na lookup mas nunca aparecem como origem.
SELECT LocationID FROM raw_zone_lookup
EXCEPT
SELECT DISTINCT PULocationID FROM raw_trips;

-- Zonas que existem na lookup mas nunca aparecem como destino.
SELECT LocationID FROM raw_zone_lookup
EXCEPT
SELECT DISTINCT DOLocationID FROM raw_trips;

-- payment_type  (LED-15)

-- Domínio: 0-4 aparecem; 5 (Unknown) e 6 (Voided) do dicionário ausentes.
SELECT payment_type, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY payment_type
ORDER BY payment_type;

-- fare_amount 

-- Faixa: -899 a 5.000 (máx. em números redondos = teto de sistema).
SELECT MIN(fare_amount) AS minimo, MAX(fare_amount) AS maximo, AVG(fare_amount) AS media
FROM raw_trips;

-- Negativos concentram-se em Dispute (4) e No charge (3) -> estorno.
SELECT payment_type, COUNT(*) AS qtd_negativos
FROM raw_trips WHERE fare_amount < 0
GROUP BY payment_type ORDER BY qtd_negativos DESC;

-- extra 

-- Valores dominantes 0/2.5/1.0 (sobretaxas fixas TLC); negativos = estorno.
SELECT extra, COUNT(*) AS qtd
FROM raw_trips
GROUP BY extra ORDER BY qtd DESC LIMIT 15;

-- mta_tax   

-- Por RatecodeID: 0.5 padrão; 0.0 em Newark (3) e Negotiated (5).
SELECT RatecodeID, mta_tax, COUNT(*) AS qtd
FROM raw_trips
GROUP BY RatecodeID, mta_tax
ORDER BY RatecodeID, qtd DESC;

-- Estorno conjunto com improvement_surcharge (-0.5 + -1.0).
SELECT mta_tax, improvement_surcharge, COUNT(*)
FROM raw_trips
GROUP BY mta_tax, improvement_surcharge
ORDER BY COUNT(*) DESC LIMIT 5;

-- tip_amount 

-- Por payment_type: cartão (1) ~95% com gorjeta; dinheiro (2) sempre 0.
SELECT payment_type, COUNT(*) AS total,
       SUM(CASE WHEN tip_amount < 0 THEN 1 ELSE 0 END) AS negativas,
       ROUND(AVG(tip_amount), 2) AS media
FROM raw_trips
GROUP BY payment_type ORDER BY payment_type;

-- tolls_amount 

-- 92,8% sem pedágio (esperado — trajetos dentro de Manhattan).
SELECT SUM(CASE WHEN tolls_amount < 0 THEN 1 ELSE 0 END) AS negativos,
       SUM(CASE WHEN tolls_amount = 0 THEN 1 ELSE 0 END) AS sem_pedagio,
       SUM(CASE WHEN tolls_amount > 0 THEN 1 ELSE 0 END) AS com_pedagio
FROM raw_trips;

-- improvement_surcharge 

-- 98,75% em $1,00; -1.0 = estorno.
SELECT improvement_surcharge, COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM raw_trips), 2) AS pct
FROM raw_trips
GROUP BY improvement_surcharge
ORDER BY improvement_surcharge;

-- total_amount + RECONCILIAÇÃO com os componentes 

-- 74,3% batem exato com a soma dos componentes.
SELECT COUNT(*) AS total,
  COUNT(*) FILTER (WHERE ABS(total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0))) <= 0.01) AS batem,
  ROUND(COUNT(*) FILTER (WHERE ABS(total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0))) <= 0.01)
    * 100.0 / COUNT(*), 2) AS pct_batem
FROM raw_trips;

-- Divergência quando não bate: mediana exatamente -2,50 (= congestion_surcharge).
SELECT ROUND(MIN(dif),2) AS min_dif, ROUND(MAX(dif),2) AS max_dif, ROUND(MEDIAN(dif),4) AS mediana_dif
FROM (
  SELECT total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0)) AS dif
  FROM raw_trips
  WHERE ABS(total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0))) > 0.01
);

-- congestion_surcharge 

-- Corridas que TOCAM Manhattan: ~91% pagam 2,5.
WITH manhattan_ids AS (SELECT LocationID FROM raw_zone_lookup WHERE Borough = 'Manhattan')
SELECT congestion_surcharge, COUNT(*) AS qnt
FROM raw_trips
WHERE PULocationID IN (SELECT LocationID FROM manhattan_ids)
   OR DOLocationID IN (SELECT LocationID FROM manhattan_ids)
GROUP BY congestion_surcharge ORDER BY qnt DESC;

-- Complemento (não tocam Manhattan): 0.0 domina. Regra geográfica confirmada.
WITH manhattan_ids AS (SELECT LocationID FROM raw_zone_lookup WHERE Borough = 'Manhattan')
SELECT congestion_surcharge, COUNT(*) AS qnt
FROM raw_trips
WHERE PULocationID NOT IN (SELECT LocationID FROM manhattan_ids)
  AND DOLocationID NOT IN (SELECT LocationID FROM manhattan_ids)
GROUP BY congestion_surcharge ORDER BY qnt DESC;

-- Airport_fee 

-- Domínio: 0 / 1.75 / -1.75 / NULO.
SELECT Airport_fee, COUNT(*) AS qnt
FROM raw_trips GROUP BY Airport_fee ORDER BY qnt DESC;

-- Buraco de 10.887 corridas de 1.75 fora de zona 'Airports':
-- 10.131 são East Elmhurst (bairro do LaGuardia). Critério de aeroporto = Airport_fee > 0.
SELECT l.Zone, l.Borough, l.service_zone, COUNT(*) AS qtd
FROM raw_trips t
JOIN raw_zone_lookup l ON t.PULocationID = l.LocationID
WHERE t.Airport_fee = 1.75 AND l.service_zone <> 'Airports'
GROUP BY l.Zone, l.Borough, l.service_zone
ORDER BY qtd DESC LIMIT 5;

-- GRUPO DE NULOS CONJUNTO (5 colunas) 

-- Interseção das 5 colunas nulas = 140.162 (sempre o mesmo grupo de linhas).
SELECT COUNT(*) AS qnt_nulidade_conjunta
FROM raw_trips
WHERE passenger_count IS NULL AND store_and_fwd_flag IS NULL AND RatecodeID IS NULL
  AND congestion_surcharge IS NULL AND Airport_fee IS NULL;

-- Causa raiz: payment_type = 0 (Flex Fare) — bate por vendor com a nulidade.
SELECT VendorID, COUNT(*) AS total_payment_zero
FROM raw_trips WHERE payment_type = 0
GROUP BY VendorID ORDER BY VendorID;

-- raw_zone_lookup (tabela de referência)

-- Nulidade real: 0 nas 4 colunas.
SELECT COUNT(*)-COUNT(LocationID) AS n_LocationID, COUNT(*)-COUNT(Borough) AS n_Borough,
       COUNT(*)-COUNT(Zone) AS n_Zone, COUNT(*)-COUNT(service_zone) AS n_service_zone
FROM raw_zone_lookup;

-- Domínios de Borough e service_zone.
SELECT Borough, COUNT(*) AS qtd FROM raw_zone_lookup GROUP BY Borough ORDER BY qtd DESC;
SELECT service_zone, COUNT(*) AS qtd FROM raw_zone_lookup GROUP BY service_zone ORDER BY qtd DESC;

-- "N/A"/"Unknown" são TEXTO LITERAL, não NULL (staging precisa normalizar).
SELECT COUNT(*) FILTER (WHERE Borough = 'N/A') AS borough_na,
       COUNT(*) FILTER (WHERE Borough = 'Unknown') AS borough_unknown,
       COUNT(*) FILTER (WHERE service_zone = 'N/A') AS servicezone_na,
       COUNT(*) FILTER (WHERE Zone = 'N/A') AS zone_na
FROM raw_zone_lookup;
