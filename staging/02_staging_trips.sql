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
fare_amount,
tip_amount,
total_amount,
payment_type,

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

DAYOFWEEK(pickup_datetime) AS pickup_day,

CASE 
    WHEN DAYOFWEEK(pickup_datetime)=1 OR DAYOFWEEK(pickup_datetime)=7
    THEN TRUE 
    ELSE FALSE 
 END AS final_de_semana,

-- Flags de Auditoria e Qualidade
CASE 
    WHEN (fare_amount < 0 OR total_amount < 0) THEN 'REJEITADO_ESTORNO'
    WHEN (dropoff_datetime <= pickup_datetime) THEN 'REJEITADO_TEMPO_INVALIDO'
    WHEN (trip_distance = 0 AND fare_amount > 0) THEN 'REJEITADO_DISTANCIA_ZERO'
    WHEN (passenger_count IS NULL OR passenger_count <= 0) THEN 'REJEITADO_PASSAGEIRO_INVALIDO'
    WHEN (
        trip_distance > 0 
        AND DATEDIFF('second', pickup_datetime, dropoff_datetime) > 0 
        AND (trip_distance / (DATEDIFF('second', pickup_datetime, dropoff_datetime) / 3600.0)) > 100
    ) THEN 'REJEITADO_VELOCIDADE_ANORMAL'
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
tip_amount,
total_amount,
payment_type,
passenger_count,
trip_duration_minutes,
trip_avg_speed_mph,
tip_percentage,
price_per_mile,
pickup_hour,
day_part,
pickup_day,
final_de_semana,

CASE 
    WHEN (fare_amount<0 or total_amount<0) THEN 'VALOR_NEGATIVO_ESTORNO'
    WHEN (dropoff_datetime <= pickup_datetime) THEN 'TEMPO_INVALIDO'
    WHEN (trip_distance = 0 AND fare_amount > 0) THEN 'DISTANCIA_ZERO_COM_COBRANCA'
    WHEN (passenger_count IS NULL OR passenger_count<=0) THEN 'VIAGEM_SEM_PASSAGEIRO'
    ELSE 'OUTRA_INCONSISTENCIA'
END AS rejection_reason, 

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
tip_amount,
total_amount,
payment_type,
trip_duration_minutes,
trip_avg_speed_mph,
tip_percentage,
price_per_mile,
pickup_hour,
day_part,
pickup_day,
final_de_semana
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