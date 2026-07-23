# Perfilamento — `yellow_tripdata_2024-01` (LED-14 a LED-18)

## Resumo executivo

Perfilamento das 19 colunas de `raw_trips` (2.964.624 linhas) e da tabela de referência
`raw_zone_lookup` (265 linhas), cobrindo tipos, volume, nulidade, domínio/cardinalidade e
valores improváveis.

O documento tem três partes:

1. **Tabela-síntese** — visão rápida por coluna.
2. **Pendências em aberto** — decisões que ainda dependem do time (tratamento na camada
   staging).
3. **Detalhamento por variável** — descrição de negócio, achados e as consultas de
   referência que sustentam cada conclusão.

As consultas versionadas ficam em [`quality/00_raw_checks.sql`](../quality/00_raw_checks.sql);
as decisões de modelagem derivadas daqui, em [`docs/hipotese_grao.md`](hipotese_grao.md).

**Legenda de status:** ✅ fechado · ⚠️ parcial

---

## Tabela-síntese

### `raw_trips`

| Coluna | Tipo | Nulidade | Domínio (resumo) | Status |
|---|---|---|---|---|
| `VendorID` | INTEGER | 0% | 1, 2, 6 — código do provedor de tecnologia, não do motorista | ✅ |
| `tpep_pickup_datetime` | TIMESTAMP | 0% | 2002–2024; 15 corridas fora de 2024 | ⚠️ |
| `tpep_dropoff_datetime` | TIMESTAMP | 0% | 56 corridas com dropoff antes do pickup | ⚠️ |
| `passenger_count` | BIGINT | 4,73% | 0–9; `0` concentrado no VendorID 1 (4,3%) | ✅ |
| `trip_distance` | DOUBLE | 0% | 0 a 312.722 milhas; outliers extremos identificados | ⚠️ |
| `RatecodeID` | BIGINT | 4,73% | 1, 2, 3, 4, 5, 6, 99 — bate com o dicionário | ✅ |
| `store_and_fwd_flag` | VARCHAR | 4,73% | N (95%), Y (0,4%) | ✅ |
| `PULocationID` | INTEGER | 0% | cobre 260 das 265 zonas | ✅ |
| `DOLocationID` | INTEGER | 0% | cobre 261 das 265 zonas | ✅ |
| `payment_type` | BIGINT | 0% | 0–4 aparecem; 5 e 6 do dicionário ausentes | ⚠️ |
| `fare_amount` | DOUBLE | 0% | -899 a 5.000; 1,3% negativo | ⚠️ |
| `extra` | DOUBLE | 0% | -7,5 a 14,25; 48 valores distintos | ✅ |
| `mta_tax` | DOUBLE | 0% | majoritariamente 0,5; exceções explicadas por RatecodeID | ✅ |
| `tip_amount` | DOUBLE | 0% | -80 a 428; padrão claro por payment_type | ✅ |
| `tolls_amount` | DOUBLE | 0% | 92,8% sem pedágio (esperado) | ✅ |
| `improvement_surcharge` | DOUBLE | 0% | 98,75% em $1,00 (vigente desde nov/2022) | ✅ |
| `total_amount` | DOUBLE | 0% | -900 a 5.000; 19.241 valores distintos | ✅ |
| `congestion_surcharge` | DOUBLE | 4,73% | ~91% das corridas em Manhattan pagam 2,5 | ✅ |
| `Airport_fee` | DOUBLE | 4,73% | 0 / 1,75 / -1,75; buraco de 10.887 corridas sem zona de aeroporto | ✅ |

> As 5 colunas com 4,73% de nulos (`passenger_count`, `RatecodeID`, `store_and_fwd_flag`,
> `congestion_surcharge`, `Airport_fee`) são nulas nas **mesmas** 140.162 linhas — ver
> [Grupo de nulos conjunto](#grupo-de-nulos-conjunto-transversal-a-5-colunas).

### `raw_zone_lookup`

| Coluna | Tipo | Nulidade | Domínio | Status |
|---|---|---|---|---|
| `LocationID` | BIGINT | 0% | 1–265 | ✅ |
| `Borough` | VARCHAR | 0% | 8 valores; `N/A` e `Unknown` como **texto literal** | ✅ |
| `Zone` | VARCHAR | 0% | 265 valores distintos (~1:1 com LocationID) | ✅ |
| `service_zone` | VARCHAR | 0% | `Airports`, `Boro Zone`, `EWR`, `N/A`, `Yellow Zone` | ✅ |

---

## Pendências em aberto

Decisões que **não** são fechadas no perfilamento e precisam ser resolvidas na camada de
tratamento (staging), com registro em [`docs/decisoes.md`](decisoes.md) quando batidas:

1. **Datas inválidas** (`tpep_*_datetime`): definir o tratamento das 15 corridas fora de
   jan/2024 e das 56 com `dropoff < pickup` — descartar ou marcar como inválidas? Volume
   desprezível (71 linhas), mas precisa acontecer **antes** de montar a `dim_tempo`.
2. **Valores monetários negativos (estorno)**: confirmar formalmente a hipótese de
   estorno/cancelamento (concentrada em `payment_type` 3 e 4) e decidir o tratamento —
   recomendação registrada: marcar com flag `is_estorno`, não excluir.
3. **Divergência com o dicionário em `payment_type`**: valores 5 (Unknown) e 6 (Voided)
   não aparecem em jan/2024 — documentar a divergência (mesmo padrão do caso
   `VendorID`/Helix), sem tratar como erro.
4. **Teto de distância** (`trip_distance`): investigar além do top 10 de distância extrema e
   definir um limiar mín./máx. de tratamento em staging (limiar de "distância improvável" já
   proposto: `> 50 mi` OU razão `dist/fare > 5`).

Todas as demais colunas foram fechadas sem pendência essencial.

---

## Detalhamento por variável

Cada coluna segue a estrutura: **o que é** → **nulidade** → **domínio/cardinalidade** →
**achados** → **pendências**, com as consultas de referência ao final.

### `VendorID` (INTEGER)

**O que é:** código do provedor de tecnologia (TPEP) que registrou a corrida — não é o
motorista nem o veículo; é a empresa cujo sistema processou o registro.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** 1 (729.732 corridas), 2 (2.234.632), 6 (260). O código 7 (Helix,
presente no dicionário de 2025) não aparece nos dados de jan/2024.

**Achados:**
- Considerando **todas as 19 colunas de negócio**, não há nenhuma duplicata de linha
  (2.964.624 = 2.964.624 distintas → 0 duplicatas).

**Pendências:** nenhuma.

```sql
SELECT VendorID, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY VendorID;
-- 2 -> 2.234.632 · 1 -> 729.732 · 6 -> 260

WITH distintas AS (
  SELECT DISTINCT VendorID, tpep_pickup_datetime, tpep_dropoff_datetime, passenger_count,
         trip_distance, RatecodeID, store_and_fwd_flag, PULocationID, DOLocationID,
         payment_type, fare_amount, extra, mta_tax, tip_amount, tolls_amount,
         improvement_surcharge, total_amount, congestion_surcharge, Airport_fee
  FROM raw_trips
)
SELECT (SELECT COUNT(*) FROM raw_trips) AS total_linhas,
       (SELECT COUNT(*) FROM distintas) AS linhas_distintas,
       (SELECT COUNT(*) FROM raw_trips) - (SELECT COUNT(*) FROM distintas) AS duplicatas;
-- 2.964.624 · 2.964.624 · 0
```

### `tpep_pickup_datetime` / `tpep_dropoff_datetime` (TIMESTAMP)

**O que é:** momento em que o taxímetro foi acionado (pickup, início) e desligado (dropoff, fim).

**Nulidade:** 0% nas duas colunas.

**Domínio:** registros entre 2002 e 2024 (o valor de 2002 é incompatível com a fonte, que é
só janeiro/2024).

**Achados:**
- 15 corridas com pickup fora do intervalo de 2024 — devem ser descartadas da análise.
- 56 corridas com dropoff antes do pickup — fisicamente impossível; volume pequeno, mas
  conceitualmente relevante.
- Corridas com pickup em janeiro e dropoff em fevereiro/2024 são **legítimas** (não contam
  como problema).

**Pendências ⚠️:** tratamento das 15 + 56 corridas (descartar? marcar como inválidas?) —
decisão de staging, ver [Pendências em aberto](#pendências-em-aberto).

```sql
SELECT MIN(tpep_pickup_datetime) AS primeira_partida, MAX(tpep_pickup_datetime) AS ultima_partida,
       MIN(tpep_dropoff_datetime) AS primeira_chegada, MAX(tpep_dropoff_datetime) AS ultima_chegada
FROM raw_trips;   -- viagem mais antiga em 2002

SELECT COUNT(*) AS total_fora_de_2024
FROM raw_trips
WHERE tpep_pickup_datetime < '2024-01-01' OR tpep_pickup_datetime >= '2025-01-01';   -- 15

SELECT COUNT(*) AS viagens_invertidas
FROM raw_trips
WHERE tpep_dropoff_datetime < tpep_pickup_datetime;   -- 56
```

### `passenger_count` (BIGINT)

**O que é:** quantidade de passageiros no veículo, campo preenchido pelo motorista.

**Nulidade:** 4,73% (140.162 linhas) — parte do grupo de nulos conjunto.

**Domínio/Cardinalidade:** 0 a 9 passageiros (11 valores distintos, incluindo NULL).

**Achados:**
- `passenger_count = 0` está concentrado quase todo no `VendorID = 1` (4,3% das corridas
  desse vendor; nos outros dois, próximo de zero).
- Valores altos (7, 8, 9), cruzados com `RatecodeID`, aparecem em corridas de aeroporto e
  tarifa negociada — coerente com vans/SUV autorizadas a levar mais de 4 passageiros.
- **Decisão técnica registrada:** não aplicar filtro para remover `passenger_count > 4`.

**Pendências:** nenhuma (o NULL é resolvido no grupo de nulos conjunto).

```sql
SELECT DISTINCT passenger_count FROM raw_trips;   -- NULL, 0..9

SELECT VendorID, COUNT(*) AS total_viagens,
       SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) AS viagens_com_zero_pass,
       ROUND(SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct
FROM raw_trips
GROUP BY VendorID;
-- 1: 729.732 / 31.369 / 4,3% · 2: 2.234.632 / 96 / 0,0% · 6: 260 / 0 / 0,0%
```

### `trip_distance` (DOUBLE)

**O que é:** distância percorrida na corrida, em milhas, reportada pelo taxímetro.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** 0 a 312.722,3 milhas (média 3,65).

**Achados:**
- A maior distância registrada (312.722,3 mi) está associada a uma tarifa de apenas $14,46,
  entre bairros vizinhos de Manhattan — erro de taxímetro, não corrida real.
- A distribuição da distância pura mostra P99,9 = 33,52 mi e um salto enorme só no P99,99
  (~2.987 mi) — a "cauda" implausível.
- **Limiar de distância improvável** definido como `trip_distance > 50 mi` **OU** razão
  `trip_distance / fare_amount > 5`, a partir de uma população de referência
  (`0 < trip_distance <= 50 AND fare_amount > 0`, onde o P99,9 da razão é 0,72). Resultado:
  **819 corridas (0,03%)** — 412 por distância, 437 por razão.
- Corridas com `trip_distance = 0` e duração de 0 s ainda aparecem com cobrança. As maiores
  taxas de zero se concentram em `RatecodeID` 5 e 6 (negociada/grupo — esperado); anômalas
  em `RatecodeID = 1` (Standard). Hipóteses: taxa mínima de cancelamento, teste de sistema
  no início do turno, ou taxímetro ligado/desligado no mesmo instante.

**Pendências ⚠️:** investigar além do top 10 de distância extrema; definir o teto de
tratamento em staging — ver [Pendências em aberto](#pendências-em-aberto).

```sql
SELECT APPROX_QUANTILE(trip_distance, 0.9)   AS p90,
       APPROX_QUANTILE(trip_distance, 0.99)  AS p99,
       APPROX_QUANTILE(trip_distance, 0.999) AS p999,
       APPROX_QUANTILE(trip_distance, 0.9999) AS p9999
FROM raw_trips;   -- 8,39 · 20,02 · 33,52 · 2.987,03

SELECT COUNT(*) FILTER (WHERE trip_distance > 50) AS dist_maior_50,
       COUNT(*) FILTER (WHERE fare_amount > 0 AND trip_distance/fare_amount > 5) AS razao_maior_5,
       COUNT(*) FILTER (WHERE trip_distance > 50 OR (fare_amount > 0 AND trip_distance/fare_amount > 5)) AS total
FROM raw_trips;   -- 412 · 437 · 819

WITH totais AS (SELECT RatecodeID, COUNT(*) AS total FROM raw_trips GROUP BY RatecodeID),
     zeros  AS (SELECT RatecodeID, COUNT(*) AS qtd_zero FROM raw_trips WHERE trip_distance = 0 GROUP BY RatecodeID)
SELECT z.RatecodeID, z.qtd_zero, t.total, ROUND(z.qtd_zero * 100.0 / t.total, 2) AS pct_zero
FROM zeros z JOIN totais t ON z.RatecodeID IS NOT DISTINCT FROM t.RatecodeID
ORDER BY pct_zero DESC;   -- 6: 85,71% · 5: 52,6% · ... · 1: 0,83%
```

### `RatecodeID` (BIGINT)

**O que é:** código da regra de tarifação vigente ao fim da corrida — define **como** o preço
foi calculado (padrão, aeroporto, negociada etc.), sem relação direta com localização.

**Nulidade:** 4,73% (grupo de nulos conjunto).

**Domínio/Cardinalidade:**

| RatecodeID | Corridas |
|---|---|
| 1 (Standard) | 2.663.350 |
| 2 (JFK) | 98.713 |
| 3 (Newark) | 7.954 |
| 4 (Nassau/Westchester) | 6.365 |
| 5 (Negotiated fare) | 19.410 |
| 6 (Group ride) | 7 |
| 99 (Null/unknown) | 28.663 |
| NULO | 140.162 |

**Achados:** todos os valores batem com o dicionário; `99` ("Null/unknown") é categoria
**válida** de origem, não um valor ausente — não deve ser tratado como NULL.

**Pendências:** nenhuma.

```sql
SELECT COALESCE(CAST(RatecodeID AS VARCHAR), 'NULO') AS RatecodeID, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY RatecodeID
ORDER BY RatecodeID;
```

### `store_and_fwd_flag` (VARCHAR)

**O que é:** indica se o sistema de bordo ficou sem conexão e reteve os dados na memória do
veículo antes de enviá-los ao provedor.

**Nulidade:** 4,73% (grupo de nulos conjunto).

**Domínio/Cardinalidade:** N (2.813.126, ~95%), Y (11.336, ~0,4%), NULO (140.162).

**Achados:** nenhum valor fora do domínio esperado (Y/N).

**Pendências:** nenhuma.

```sql
SELECT COALESCE(store_and_fwd_flag, 'NULO') AS store_and_fwd_flag, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY store_and_fwd_flag
ORDER BY store_and_fwd_flag;
```

### `PULocationID` / `DOLocationID` (INTEGER)

**O que é:** zona de táxi (uma das 265 da TLC, ver `raw_zone_lookup`) em que a corrida
começou (PU, embarque) e terminou (DO, desembarque).

**Nulidade:** 0% nas duas.

**Domínio/Cardinalidade:** `PULocationID` cobre 260 das 265 zonas; `DOLocationID`, 261 das 265.

**Achados:**
- Zonas ausentes em `PULocationID`: 5, 99, 103, 104, 110.
- Zonas ausentes em `DOLocationID`: 103, 104, 110, 199.
- Zonas sem correspondência em **nenhuma** das duas pontas: 103, 104, 110.

**Pendências:** nenhuma essencial (entender *por que* essas zonas nunca aparecem seria
enriquecimento, não bloqueio).

```sql
SELECT LocationID FROM raw_zone_lookup
EXCEPT
SELECT DISTINCT PULocationID FROM raw_trips;   -- 5, 99, 103, 104, 110

SELECT LocationID FROM raw_zone_lookup
EXCEPT
SELECT DISTINCT DOLocationID FROM raw_trips;   -- 103, 104, 110, 199
```

### `payment_type` (BIGINT)

**O que é:** forma de pagamento usada na corrida.

**Nulidade:** 0%.

**Domínio/Cardinalidade:**

| payment_type | Corridas |
|---|---|
| 0 (Flex Fare trip) | 140.162 |
| 1 (Credit card) | 2.319.046 |
| 2 (Cash) | 439.191 |
| 3 (No charge) | 19.597 |
| 4 (Dispute) | 46.628 |

**Achados:**
- Os valores 5 (Unknown) e 6 (Voided trip) do dicionário não aparecem em jan/2024.
- `payment_type = 0` corresponde **exatamente** (correspondência total e bidirecional) ao
  grupo de nulos conjunto de 5 outras colunas — **é a causa raiz** daquele grupo de nulos.

**Pendências ⚠️:** documentar a divergência com o dicionário (5 e 6 ausentes), mesmo padrão
do caso `VendorID`/Helix.

```sql
SELECT payment_type, COUNT(*) AS corridas_associadas
FROM raw_trips
GROUP BY payment_type
ORDER BY payment_type;
```

### `fare_amount` (DOUBLE)

**O que é:** tarifa calculada pelo taxímetro com base em tempo e distância — não inclui
sobretaxas.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** -899,0 a 5.000,0 (média 18,18).

**Achados:**
- 37.448 valores negativos (1,3%) e 893 zerados — hipótese de estorno/cancelamento para os
  negativos, ainda não confirmada formalmente. Concentram-se em Dispute (4) e Cash (2).
- Valores máximos em números redondos (5000.0 e 2500.0 exatos, repetidos) — sugere teto de
  sistema, não tarifa real.
- Distribuição: maioria entre $10–30 (1.478.047), faixa esperada para deslocamentos urbanos.

**Pendências:** decisão sobre tratamento dos negativos → [Pendências em aberto](#pendências-em-aberto).

```sql
SELECT MIN(fare_amount) AS minimo, MAX(fare_amount) AS maximo, AVG(fare_amount) AS media
FROM raw_trips;   -- -899,0 · 5.000,0 · 18,175

SELECT payment_type, COUNT(*) AS qtd_negativos
FROM raw_trips WHERE fare_amount < 0
GROUP BY payment_type ORDER BY qtd_negativos DESC;   -- 4: 21.406 · 2: 8.208 · 3: 5.740 · 0: 2.066 · 1: 28
```

### `extra` (DOUBLE)

**O que é:** extras e sobretaxas diversas somadas à tarifa (ex.: hora de pico, tarifa noturna).

**Nulidade:** 0%.

**Domínio/Cardinalidade:** -7,5 a 14,25 (média 1,45); 48 valores distintos.

**Achados:**
- Valores dominantes (0.0, 2.5, 1.0) confirmam as sobretaxas fixas do NYC TLC (pico $2,50,
  noturna $1,00).
- Valores negativos (17.548 linhas) interpretados como estorno, mesmo padrão de `fare_amount`.

**Pendências:** nenhuma essencial.

```sql
SELECT extra, COUNT(*) AS qtd
FROM raw_trips
GROUP BY extra ORDER BY qtd DESC LIMIT 15;
-- 0.0 · 2.5 · 1.0 · 5.0 · 3.5 · ... · -1.0 · -2.5 ...
```

### `mta_tax` (DOUBLE)

**O que é:** taxa estadual fixa (historicamente $0,50) cobrada em corridas dentro da área de
cobertura da MTA, acionada com base na tarifa medida em uso.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** majoritariamente 0.5.

**Achados:**
- `0.0` predomina em `RatecodeID = 3` (Newark — fora do distrito da MTA) e aparece misto em
  `RatecodeID = 5` (negociada, que não segue a regra fixa).
- Correlação forte com `improvement_surcharge`: 97% das corridas pagam as duas sobretaxas
  juntas, e o estorno aparece conjunto (`-0.5 + -1.0`) — um mesmo evento
  (cancelamento/disputa) reverte as duas taxas ao mesmo tempo.

**Pendências:** nenhuma essencial.

```sql
SELECT RatecodeID, mta_tax, COUNT(*) AS qtd
FROM raw_trips
GROUP BY RatecodeID, mta_tax
ORDER BY RatecodeID, qtd DESC;

SELECT mta_tax, improvement_surcharge, COUNT(*)
FROM raw_trips
GROUP BY mta_tax, improvement_surcharge
ORDER BY COUNT(*) DESC LIMIT 5;
-- 0.5 / 1.0 -> 2.899.869 · -0.5 / -1.0 -> 34.432 · 0.0 / 1.0 -> 27.840 ...
```

### `tip_amount` (DOUBLE)

**O que é:** valor da gorjeta. Preenchido automaticamente só para pagamentos em cartão;
gorjetas em dinheiro não entram nesse campo.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** -80,0 a 428,0 (média 3,34).

**Achados:**
- `payment_type = 1` (cartão): ~95% das corridas com gorjeta (média $4,17).
- `payment_type = 2` (dinheiro): média $0,00 — confirma a regra do dicionário.
- Gorjetas negativas concentradas em `payment_type` 3 (No charge) e 4 (Dispute) — estorno.
- Outliers com `fare_amount = 0.01` e gorjeta alta (até $428): hipótese de lançamento avulso
  na maquininha (ajuste de conta sem corrida real de taxímetro).
- Gorjeta maior que a tarifa: dois perfis — proporcional (corrida longa, gorjeta alta mas
  coerente) e suspeito de erro de digitação (corrida curta, gorjeta desproporcional).
- **Recomendação registrada:** usar coluna booleana `is_tip_outlier` (`tip_amount > 50` ou
  `pct_gorjeta > 100%`) no modelo, em vez de descartar os valores.

**Pendências:** nenhuma essencial.

```sql
SELECT payment_type, COUNT(*) AS total,
       SUM(CASE WHEN tip_amount < 0 THEN 1 ELSE 0 END) AS negativas,
       ROUND(AVG(tip_amount), 2) AS media
FROM raw_trips
GROUP BY payment_type ORDER BY payment_type;

-- outliers de gorjeta (lançamento avulso / erro de digitação)
SELECT trip_distance, fare_amount, tip_amount, total_amount, payment_type,
       ROUND((tip_amount / NULLIF(fare_amount, 0)) * 100, 2) AS pct_gorjeta_sobre_tarifa
FROM raw_trips
WHERE fare_amount > 0 AND tip_amount > fare_amount
ORDER BY pct_gorjeta_sobre_tarifa DESC LIMIT 10;
```

### `tolls_amount` (DOUBLE)

**O que é:** total de pedágios pagos durante a corrida.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** 92,8% das corridas sem pedágio.

**Achados:** esperado — a maioria dos trajetos de NY acontece dentro de Manhattan; os
pedágios existentes cobrem trajetos que cruzam pontes/túneis tarifados.

**Pendências:** nenhuma.

```sql
SELECT SUM(CASE WHEN tolls_amount < 0 THEN 1 ELSE 0 END) AS negativos,
       SUM(CASE WHEN tolls_amount = 0 THEN 1 ELSE 0 END) AS sem_pedagio,
       SUM(CASE WHEN tolls_amount > 0 THEN 1 ELSE 0 END) AS com_pedagio
FROM raw_trips;
```

### `improvement_surcharge` (DOUBLE)

**O que é:** sobretaxa fixa por corrida, em vigor desde 2015, destinada a financiar melhorias
de acessibilidade nos veículos (regulada pela TLC).

**Nulidade:** 0%.

**Domínio/Cardinalidade:** 98,75% em $1,00 (valor vigente desde nov/2022).

**Achados:**
- Parte em $0,30 — taxa histórica anterior à mudança de nov/2022.
- `-1.0` (35.500 ocorrências, 1,2%) bate com o volume de corridas anuladas/disputa — anula a
  taxa padrão nesses casos.

**Pendências:** nenhuma.

```sql
SELECT improvement_surcharge, COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM raw_trips), 2) AS pct
FROM raw_trips
GROUP BY improvement_surcharge
ORDER BY improvement_surcharge;
```

### `total_amount` (DOUBLE)

**O que é:** valor total oficialmente cobrado do passageiro (tarifa + sobretaxas). Não inclui
gorjetas em dinheiro.

**Nulidade:** 0%.

**Domínio/Cardinalidade:** -900,0 a 5.000,0 (média 26,80); 19.241 valores distintos —
cardinalidade alta esperada, por ser a soma de vários componentes.

**Achados — distribuição:**

| Faixa | Corridas |
|---|---|
| 10 a 30 | 2.191.202 |
| 30 a 100 | 634.029 |
| até 10 | 63.497 |
| acima de 100 | 39.976 |
| negativo | 35.504 |
| zero | 416 |

- **Reconciliação com os componentes:** 74,3% das linhas batem exato (tolerância $0,01) com
  `fare_amount + extra + mta_tax + tip_amount + tolls_amount + improvement_surcharge +
  congestion_surcharge + Airport_fee`. Quando não bate, a divergência é pequena e estruturada
  (mediana exatamente −$2,50 = `congestion_surcharge`). Se `total_amount` for recomputado na
  modelagem, revisitar esse tratamento.

**Pendências:** nenhuma essencial.

```sql
SELECT COUNT(*) AS total,
  COUNT(*) FILTER (WHERE ABS(total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0))) <= 0.01) AS batem,
  ROUND(COUNT(*) FILTER (WHERE ABS(total_amount - (fare_amount+extra+mta_tax+tip_amount+tolls_amount
    +improvement_surcharge+COALESCE(congestion_surcharge,0)+COALESCE(Airport_fee,0))) <= 0.01)
    * 100.0 / COUNT(*), 2) AS pct_batem
FROM raw_trips;   -- 2.964.624 · 2.202.786 · 74,3%
```

### `congestion_surcharge` (DOUBLE)

**O que é:** sobretaxa estadual de congestionamento de NY, aplicada a corridas que começam,
terminam **ou passam** pela Zona de Congestionamento de Manhattan (abaixo da 96th Street).
`raw_zone_lookup` não distingue esse limite de rua — a análise usa `Borough = 'Manhattan'`
como aproximação.

**Nulidade:** 4,73% (grupo de nulos conjunto).

**Domínio/Cardinalidade:** ~91% das corridas que tocam Manhattan (embarque ou desembarque)
pagam 2.5.

**Achados:**
- No complemento (corridas que não tocam Manhattan em nenhuma ponta), `0.0` domina (134.636
  de 153.497) — a regra geográfica se confirma nos dois sentidos.
- 10.145 casos de 2.5 fora de Manhattan são atribuídos a corridas "de passagem" — a regra
  cobre início, fim **ou** trajeto, e os dados só registram origem/destino, não a rota.
- `-2.5` é o mesmo padrão de estorno das outras sobretaxas.

**Pendências:** nenhuma essencial — a limitação geográfica (precisão só por borough, não por
rua) está documentada em [`hipotese_grao.md`](hipotese_grao.md) §8.10.

```sql
WITH manhattan_ids AS (SELECT LocationID FROM raw_zone_lookup WHERE Borough = 'Manhattan')
SELECT congestion_surcharge, COUNT(*) AS qnt
FROM raw_trips
WHERE PULocationID IN (SELECT LocationID FROM manhattan_ids)
   OR DOLocationID IN (SELECT LocationID FROM manhattan_ids)
GROUP BY congestion_surcharge ORDER BY qnt DESC;
-- 2.5 -> 2.567.610 · NULO -> 131.827 · 0.0 -> 83.241 · -2.5 -> 28.443 ...
```

### `Airport_fee` (DOUBLE)

**O que é:** taxa aplicada apenas em embarques nos aeroportos LaGuardia e JFK.

**Nulidade:** 4,73% (grupo de nulos conjunto).

**Domínio/Cardinalidade:** 0.0 (2.586.789), 1.75 (232.752), -1.75 (4.921) + NULO.

**Achados:**
- Regra "só embarque" confirmada: desembarque em aeroporto sem embarque em aeroporto tem
  `Airport_fee = 0.0` em ~90% dos casos.
- Newark (EWR) descartado como anomalia: `PULocationID = 1` (Newark) sempre tem
  `Airport_fee = 0.0`, nunca 1.75 — a exclusão de Newark está correta.
- **Buraco resolvido:** dos 232.752 cobrados a 1.75, só 221.865 têm PU numa zona
  `service_zone = 'Airports'`. As 10.887 restantes → 10.131 são **East Elmhurst**, o bairro
  do Queens onde fica o LaGuardia. **Conclusão:** o critério de "corrida de aeroporto" tem de
  ser `Airport_fee > 0`, **não** `service_zone = 'Airports'`.

**Pendências:** nenhuma.

```sql
SELECT Airport_fee, COUNT(*) AS qnt
FROM raw_trips GROUP BY Airport_fee ORDER BY qnt DESC;

SELECT l.Zone, l.Borough, l.service_zone, COUNT(*) AS qtd
FROM raw_trips t
JOIN raw_zone_lookup l ON t.PULocationID = l.LocationID
WHERE t.Airport_fee = 1.75 AND l.service_zone <> 'Airports'
GROUP BY l.Zone, l.Borough, l.service_zone
ORDER BY qtd DESC LIMIT 5;   -- East Elmhurst -> 10.131 ...
```

---

## Grupo de nulos conjunto (transversal a 5 colunas)

**O que é:** `passenger_count`, `RatecodeID`, `store_and_fwd_flag`, `congestion_surcharge` e
`Airport_fee` ficam nulas exatamente nas **mesmas** 140.162 linhas — tratado à parte por
afetar várias colunas ao mesmo tempo, com causa raiz comum.

**Achados:**
- A interseção das 5 colunas nulas (todas ao mesmo tempo) dá exatamente 140.162 linhas — o
  mesmo total de nulos de cada coluna isoladamente, confirmando que é sempre o mesmo grupo.
- **Causa raiz:** `payment_type = 0` (Flex Fare trip) — correspondência total e bidirecional
  (toda linha nula tem `payment_type = 0`, e todo `payment_type = 0` é nulo nessas 5 colunas).
- Distribuição por vendor: VendorID 2 = 91.447, VendorID 1 = 48.455, VendorID 6 = 260 (100%
  das corridas do vendor 6 caem nesse grupo).

**Pendências:** nenhuma — causa fechada. O tratamento (default vs. flag vs. `Unknown`) é
decisão de staging registrada em [`hipotese_grao.md`](hipotese_grao.md) §8.1.

```sql
SELECT COUNT(*) AS qnt_nulidade_conjunta
FROM raw_trips
WHERE passenger_count IS NULL AND store_and_fwd_flag IS NULL AND RatecodeID IS NULL
  AND congestion_surcharge IS NULL AND Airport_fee IS NULL;   -- 140.162

SELECT VendorID, COUNT(*) AS total_payment_zero
FROM raw_trips WHERE payment_type = 0
GROUP BY VendorID ORDER BY VendorID;   -- 1: 48.455 · 2: 91.447 · 6: 260
```

---

## Perfilamento da tabela de apoio `raw_zone_lookup`

**Nulidade:** 0% nas quatro colunas (`LocationID`, `Borough`, `Zone`, `service_zone`).

**Domínios:**

| Borough | Zonas |   | service_zone | Zonas |
|---|---|---|---|---|
| Queens | 69 |   | Boro Zone | 205 |
| Manhattan | 69 |   | Yellow Zone | 55 |
| Brooklyn | 61 |   | N/A | 2 |
| Bronx | 43 |   | Airports | 2 |
| Staten Island | 20 |   | EWR | 1 |
| Unknown | 1 |   | | |
| EWR | 1 |   | | |
| N/A | 1 |   | | |

**Achados:**
- `N/A` e `Unknown` aparecem em `Borough`, `service_zone` e `Zone` como **texto literal**, não
  como `NULL`. **dim_zona:** normalizar explicitamente ao montar a dimensão (um filtro
  `IS NULL` não os captura).

**Pendências:** nenhuma.

```sql
SELECT COUNT(*)-COUNT(LocationID) AS n_LocationID, COUNT(*)-COUNT(Borough) AS n_Borough,
       COUNT(*)-COUNT(Zone) AS n_Zone, COUNT(*)-COUNT(service_zone) AS n_service_zone
FROM raw_zone_lookup;   -- 0 · 0 · 0 · 0

SELECT COUNT(*) FILTER (WHERE Borough = 'N/A') AS borough_na,
       COUNT(*) FILTER (WHERE Borough = 'Unknown') AS borough_unknown,
       COUNT(*) FILTER (WHERE service_zone = 'N/A') AS servicezone_na,
       COUNT(*) FILTER (WHERE Zone = 'N/A') AS zone_na
FROM raw_zone_lookup;   -- 1 · 1 · 2 · 1
```
