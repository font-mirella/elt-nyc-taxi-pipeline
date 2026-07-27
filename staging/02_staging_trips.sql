-- ==========================================================
-- STAGING 02 - Tratamentos e atributos derivados
--
-- Objetivos:
-- 1. Calcular atributos derivados para análise.
-- 2. Tratar registros inconsistentes.
-- 3. Padronizar regras de negócio.
--
-- Fonte:
-- staging_trips (resultado do 01_staging_trips.sql)
-- ==========================================================

-- =====================================
-- Atributos derivados
-- =====================================

CREATE OR REPLACE TABLE  stg_yellow_trips AS
SELECT
--Metadados e chaves
vendor_id,
pickup_datetime,
dropoff_datetime,
trip_distance,
passenger_count,
ratecode_id,
store_and_fwd_flag,
pu_location_id,
do_location_id,
fare_amount,
extra,
mta_tax,
tip_amount,
tolls_amount,
improvement_surcharge,
total_amount,
congestion_surcharge,
payment_type,
airport_fee,

--Duração da viagem
ROUND(DATEDIFF(
    'second',
    pickup_datetime,
    dropoff_datetime
)/60.0,2) AS trip_duration_minutes,

--Velocidade Media Mph
CASE 
    WHEN DATEDIFF('second',pickup_datetime,dropoff_datetime)>0
    THEN ROUND(trip_distance /
        (
            DATEDIFF('second',
                      pickup_datetime,
                      dropoff_datetime)
            /3600.0
        ),2) 
    ELSE NULL
END AS trip_avg_speed_mph,

-- Porcentagem de gorjeta (Apenas Cartão de Crédito)
CASE 
        WHEN payment_type = 1 AND fare_amount > 0 
        THEN ROUND((tip_amount / fare_amount) * 100.0, 2)
        ELSE NULL 
    END AS tip_percentage,

-- Preço por Milha
CASE 
    WHEN trip_distance>0
    THEN ROUND(total_amount/trip_distance,2)
    ELSE NULL
   END AS  price_per_mile,

-- Atributos Temporais
EXTRACT(HOUR FROM pickup_datetime) AS pickup_hour,

CASE 
    WHEN EXTRACT(HOUR FROM pickup_datetime) BETWEEN 6 AND 11 THEN 'Manhã'
    WHEN EXTRACT(HOUR FROM pickup_datetime) BETWEEN 12 AND 17 THEN 'Tarde'
    WHEN EXTRACT(HOUR FROM pickup_datetime) BETWEEN 18 AND 23 THEN 'Noite'
    ELSE 'Madrugada'
END AS day_part,

-- DAYOFWEEK no DuckDB é 0-indexado com domingo=0...sábado=6 (validado em
-- model/dims/01_dim_data.sql) - não a convenção 1=domingo/7=sábado.
DAYOFWEEK(pickup_datetime) AS pickup_day,

CASE
    WHEN DAYOFWEEK(pickup_datetime)=0 OR DAYOFWEEK(pickup_datetime)=6
    THEN TRUE
    ELSE FALSE
 END AS final_de_semana,

-- Estorno (regras_limpeza.md item 2): mantém a linha, não exclui - quem consome decide se soma
fare_amount < 0 AS is_estorno,

-- Velocidade anômala (regras_limpeza.md item 5): mantém a linha, não exclui - limiar >50mph
-- validado por quantil (p99,9), mesma assinatura de erro de captura do item 4
DATEDIFF('second', pickup_datetime, dropoff_datetime) > 0
    AND trip_distance > 0
    AND (trip_distance / (DATEDIFF('second', pickup_datetime, dropoff_datetime) / 3600.0)) > 50
    AS is_speed_outlier,

-- Distância improvável (regras_limpeza.md item 4): limiar validado por quantil exato
-- (p99,9 dist=29,5mi, p99,9 razão dist/fare=0,44), versionado em quality/00_raw_checks.sql
trip_distance > 50
    OR (fare_amount > 0 AND trip_distance / fare_amount > 5)
    AS is_distance_outlier,

-- Gorjeta atípica (regras_limpeza.md item 7): tip>50 (lançamento avulso) ou tip>fare
-- (possível erro de digitação), mesmo critério versionado em quality/00_raw_checks.sql
tip_amount > 50
    OR (fare_amount > 0 AND tip_amount > fare_amount)
    AS is_tip_outlier,

-- Teto de sistema (regras_limpeza.md item 11): valores máximos concentrados em 5000/2500
-- exatos, não tarifas reais (docs/hipotese_grao.md §8.12)
fare_amount IN (2500.0, 5000.0)
    OR total_amount IN (2500.0, 5000.0)
    AS is_fare_outlier,

-- Critério de aeroporto (regras_limpeza.md item 8): Airport_fee > 0, não service_zone =
-- 'Airports' (perderia ~10.887 corridas de East Elmhurst/LaGuardia fora da zona oficial)
COALESCE(airport_fee, 0) > 0 AS is_aeroporto,

-- Flags de Auditoria e Qualidade
-- Distância zero com cobrança (regras_limpeza.md item 4b) não é rejeitada aqui: correlação
-- duração x tarifa continua fraca para RatecodeID=1, e para as demais tarifas (2, 5, 6...)
-- distância zero + cobrança é o padrão esperado de tarifa fixa/negociada, não anomalia.
CASE
    -- regras_limpeza.md item 1: fora do escopo temporal do desafio - mesmo limite auditado
    -- em quality/00_raw_checks.sql (15 linhas fora do ano 2024)
    WHEN (pickup_datetime < '2024-01-01' OR pickup_datetime >= '2025-01-01') THEN 'REJEITADO_FORA_DO_PERIODO'
    -- regras_limpeza.md item 1: dropoff antes do pickup viola a física do evento - limite
    -- estrito (<), igual ao auditado em quality/00_raw_checks.sql (56 linhas); dropoff==pickup
    -- é duração zero legítima (mesma categoria de trip_distance=0), não é a mesma anomalia
    WHEN (dropoff_datetime < pickup_datetime) THEN 'REJEITADO_DROPOFF_ANTES_PICKUP'
    ELSE 'APROVADO'
END AS status_registro
FROM staging_trips;


-- =====================================
-- Tratamento de inconsistências
-- =====================================
CREATE OR REPLACE TABLE rejected_trips AS
SELECT
vendor_id,
pickup_datetime,
dropoff_datetime,
trip_distance,
fare_amount,
extra,
mta_tax,
tip_amount,
tolls_amount,
improvement_surcharge,
total_amount,
congestion_surcharge,
payment_type,
airport_fee,
passenger_count,
ratecode_id,
store_and_fwd_flag,
pu_location_id,
do_location_id,
trip_duration_minutes,
trip_avg_speed_mph,
tip_percentage,
price_per_mile,
pickup_hour,
day_part,
pickup_day,
final_de_semana,
is_estorno,
is_speed_outlier,
is_distance_outlier,
is_tip_outlier,
is_fare_outlier,
is_aeroporto,
-- Reaproveita status_registro em vez de recalcular a classificação (evita as duas
-- lógicas divergirem de novo, como já aconteceu antes com REJEITADO_VELOCIDADE_ANORMAL)
status_registro AS rejection_reason
FROM stg_yellow_trips
WHERE status_registro LIKE 'REJEITADO%';

-- =====================================
-- RESULTADO POS PROCESSAMENTO DE INCOSISTENCIAS
-- =====================================
CREATE OR REPLACE TABLE approved_trips AS
SELECT
vendor_id,
pickup_datetime,
dropoff_datetime,
trip_distance,
fare_amount,
extra,
mta_tax,
tip_amount,
tolls_amount,
improvement_surcharge,
total_amount,
congestion_surcharge,
payment_type,
airport_fee,
passenger_count,
ratecode_id,
store_and_fwd_flag,
pu_location_id,
do_location_id,
trip_duration_minutes,
trip_avg_speed_mph,
tip_percentage,
price_per_mile,
pickup_hour,
day_part,
pickup_day,
final_de_semana,
is_estorno,
is_speed_outlier,
is_distance_outlier,
is_tip_outlier,
is_fare_outlier,
is_aeroporto
FROM stg_yellow_trips
WHERE status_registro = 'APROVADO';

-- ====================================================================
-- Validação de Integridade e Contagem de Registros
-- Garante que: Total Staging = Total Aprovados + Total Rejeitados
-- ====================================================================

SELECT 
    (SELECT COUNT(*) FROM stg_yellow_trips) AS total_staging,
    (SELECT COUNT(*) FROM approved_trips) AS total_aprovados,
    (SELECT COUNT(*) FROM rejected_trips) AS total_rejeitados,
    
     --Soma das duas tabelas derivadas
    ((SELECT COUNT(*) FROM approved_trips) + 
     (SELECT COUNT(*) FROM rejected_trips)) AS soma_conferencia,

     --Retorna TRUE se a contagem for 100% exata
    CASE 
        WHEN (SELECT COUNT(*) FROM stg_yellow_trips) = 
             ((SELECT COUNT(*) FROM approved_trips) + (SELECT COUNT(*) FROM rejected_trips)) 
        THEN TRUE 
        ELSE FALSE 
    END AS contagem_valida;