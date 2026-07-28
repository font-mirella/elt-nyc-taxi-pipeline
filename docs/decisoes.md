# Decisões do projeto

Registro das decisões não óbvias tomadas ao longo do desafio, com a justificativa, para o time todo (assíncrono) entender o porquê sem precisar perguntar.

## 2026-07-18 — DuckDB roda via Docker Compose

Em vez de exigir instalação local do DuckDB CLI, o `Dockerfile`/`docker-compose.yml` sobem um container com a versão exata pinada (`DUCKDB_VERSION` no `Dockerfile`). Garante que os 5 integrantes e a LED, ao reproduzir o pipeline, usem a mesma versão do banco — evita divergência de comportamento entre versões do DuckDB.

## 2026-07-18 — Arquivos de dados brutos não versionados no Git

`raw/data/` (parquet ~48MB + CSV) está no `.gitignore`. Repositório fica leve e sem depender de Git LFS (que exigiria instalação extra por parte de quem clonar, inclusive a LED). Em troca, buscar os arquivos deixa de ser 100% automático: o README documenta os links diretos e o caminho local esperado, e é um passo manual antes de rodar `docker compose run`.

## 2026-07-18 — Colunas de linhagem `_loaded_at` e `_source_file` na camada raw

As tabelas `raw_trips` e `raw_zone_lookup` recebem duas colunas extras além das originais: `_loaded_at` (timestamp da carga) e `_source_file` (nome do arquivo de origem). São puramente aditivas — nenhuma coluna original é renomeada, convertida ou removida — então não violam o princípio de a camada bruta ser fiel à fonte. Servem só para auditoria/rastreabilidade.

## 2026-07-24 — Regras de limpeza fecham as pendências do perfilamento (LED-19)

`docs/regras_limpeza.md` fecha, com regra final e justificativa, as 5 pendências deixadas em aberto por `docs/perfilamento_notas.md` e as considerações de `docs/hipotese_grao.md` §8 — sem re-derivar nenhum número, só decidindo o que fazer com o que já estava evidenciado.

Duas decisões valem destacar por afetarem a modelagem: (1) as 71 linhas com data inválida (fora de jan/2024 ou dropoff antes do pickup) são as únicas excluídas da fato — todo o resto (estornos, distância improvável, gorjeta atípica, teto de tarifa) é mantido com flag booleana (`is_estorno`, `is_distance_outlier`, `is_tip_outlier`, `is_fare_outlier`), para o consumo analítico decidir incluir ou não, em vez da staging decidir por todos os casos de uso; (2) o grupo de nulos ligado a `payment_type = 0` (Flex Fare) recebe um membro dimensional "Não se aplica", diferente do membro "Desconhecido" usado para `RatecodeID = 99` — são causas diferentes de ausência e não podem virar a mesma categoria.

## 2026-07-24 — `staging_trips`/`staging_zone_lookup` com TRY_CAST defensivo (LED-20 a LED-22)

`staging/01_staging_trips.sql` e `staging/02_staging_zone_lookup.sql` renomeiam todas as colunas para snake_case e usam `TRY_CAST` explícito em cada campo, mesmo o Parquet já chegando tipado corretamente hoje — garante que um mês futuro com valor malformado vire `NULL` em vez de quebrar o `CREATE OR REPLACE TABLE` inteiro (exigência da seção 04, item 4 do desafio).

Nulos do grupo `payment_type = 0` (ver LED-19) não são coalescidos em staging — continuam `NULL`, conforme a regra 6 de `docs/regras_limpeza.md`; o mapeamento para o membro "Não se aplica" fica para a etapa de dimensões (LED-26+), não para a staging.

`docs/regras_limpeza.md` #9 (normalizar `'N/A'`/`'Unknown'` como texto literal) foi implementado direto em `staging_zone_lookup`, não esperando a etapa de `dim_zona` — como é uma limpeza de valor (não uma decisão de modelagem), fazia mais sentido resolver na staging.

`quality/01_staging_checks.sql` usa `error()` para interromper `run_all.sql` se a duplicidade (checada em todas as 19 colunas de negócio) ou a integridade referencial de zona voltarem a aparecer — hoje ambas são 0, conforme o perfilamento, mas o pipeline falha alto em vez de silenciosamente aceitar regressão num mês futuro. Códigos fora do domínio (`vendor_id`, `ratecode_id`, `payment_type`) só são contados, não bloqueiam — regra 3 de `docs/regras_limpeza.md` trata isso como divergência a documentar, não erro.

**Bug corrigido de passagem:** `quality/00_raw_checks.sql` (camada de perfilamento, já mesclada) tinha uma consulta que comparava `PULocationID`/`DOLocationID` com `IS NOT DISTINCT FROM (SELECT LocationID FROM manhattan_ids)` — uma subquery de 69 linhas usada em posição escalar, o que quebra `run_all.sql` inteiro com DuckDB 1.1.3 (`scalar subquery... can only return a single row`). Trocado para `NOT IN`, que é a semântica que a consulta sempre pretendeu (corridas que não tocam Manhattan em nenhuma ponta). Descoberto ao validar que o pipeline reconstrói do zero antes de abrir PR, conforme o fluxo de trabalho do README.

## 2026-07-25 - `staging_trips` (LED 23 A 25) Arquitetura de quarentena, métricas derivadas e saneamento de dados

`stg_yellow_trips` consolida a tabela mestre da camada de staging utilizando a instrução CREATE OR REPLACE TABLE para garantir idempotência total (permite reexecutar o pipeline sem duplicação de linhas ou necessidade de limpeza manual). 
Todas as colunas foram padronizadas em snake_case e tipadas explicitamente. Na mesma etapa, são calculadas quatro métricas essenciais tratadas contra erros de runtime:Duração (trip_duration_minutes): Cálculo de DATEDIFF('second', pickup_datetime, dropoff_datetime) / 60.0, arredondado em 2 casas decimais;Velocidade Média (trip_avg_speed_mph): Razão entre trip_distance e o tempo em horas (DATEDIFF em segundos / 3600.0), encapsulada em um CASE WHEN para retornar NULL caso a duração seja  <=0, evitando erros fatais de divisão por zero;Taxa de Gorjeta (tip_percentage): Calculada como (tip_amount / fare_amount) * 100.0. 
Por regra de negócio, a fórmula é restrita a pagamentos via cartão de crédito (payment_type = 1) com fare_amount > 0 (as gorjetas em dinheiro não são registradas no taxímetro, o que geraria um falso viés de gorjeta zero se incluídas);Custo por Milha (price_per_mile): Razão total_amount / trip_distance, calculada apenas quando trip_distance > 0.
Para suporte a análises temporais executivas sem reprocessamento em dashboards, a tabela extrai pickup_hour, pickup_day (DAYOFWEEK), o flag booleano final_de_semana (DAYOFWEEK IN (1, 7)) e categoriza a hora de embarque na coluna day_part em quatro blocos: Madrugada (00h–05h), Manhã (06h–11h), Tarde (12h–17h) e Noite (18h–23h).
Para atender à exigência de rastreabilidade (sem exclusão silenciosa via DELETE), a consolidação cria a coluna de diagnóstico status_registro, que mapeia apenas as anomalias sem leitura de negócio possível (regra 1 de `docs/regras_limpeza.md` — as únicas que justificam exclusão), na ordem: REJEITADO_FORA_DO_PERIODO: se pickup_datetime cai fora de jan/2024; REJEITADO_DROPOFF_ANTES_PICKUP: se dropoff_datetime < pickup_datetime (limite estrito, igual ao auditado em `quality/00_raw_checks.sql`). Registros que passam em todas as validações recebem a marcação 'APROVADO'.

**Correção de 2026-07-27:** a versão original desta consolidação também rejeitava `passenger_count <= 0` e usava `dropoff_datetime <= pickup_datetime` (não estrito). Nenhuma das duas está nas 11 regras de `docs/regras_limpeza.md` — a primeira descartava ~31 mil corridas legítimas do VendorID 1 (achado do próprio perfilamento, `passenger_count = 0` é padrão conhecido, não erro) e a segunda rejeitava 814 corridas de duração zero além das 56 auditadas. Ambas foram removidas/corrigidas para a quarentena bater exatamente com o documentado (71 rejeitados: 15 fora do período + 56 dropoff antes do pickup). Na mesma correção, foram adicionadas as flags que faltavam desde a entrega original — `is_distance_outlier` (regra 4), `is_tip_outlier` (regra 7), `is_fare_outlier` (regra 11) e `is_aeroporto` (regra 8) — e propagadas as colunas monetárias (`extra`, `mta_tax`, `tolls_amount`, `improvement_surcharge`, `congestion_surcharge`) que a fato precisa como medidas aditivas.

Casos "incomuns" (com leitura de negócio) não são excluídos, apenas flagados na própria linha: is_estorno (fare_amount < 0, regra 2) e is_speed_outlier (velocidade implícita > 50mph, limiar validado por quantil — p99,9 = 49,1mph — regra 5). A distância zero com cobrança (regra 4b) não vira flag nesta entrega: a correlação duração×tarifa segue fraca para RatecodeID=1, e para as demais tarifas (negociada/fixa) esse padrão é esperado, não anomalia.

`rejected_trips` cria a tabela dedicada de quarentena via CREATE OR REPLACE TABLE, filtrando exclusivamente as linhas onde status_registro LIKE 'REJEITADO%'. A coluna rejection_reason reaproveita o valor de status_registro (em vez de recalcular a classificação), evitando que as duas lógicas divirjam. A tabela preserva os mesmos atributos de `staging_trips` (incluindo ratecode_id, store_and_fwd_flag, pu_location_id, do_location_id e passenger_count) mais as métricas derivadas.
`approved_trips` materializa a tabela refinada contendo apenas as corridas marcadas como 'APROVADO', com o mesmo schema de `rejected_trips` (exceto rejection_reason) — pronta para consumo na camada de Analytics/BI, incluindo join com `staging_zone_lookup` por pu_location_id/do_location_id, sem a necessidade de cláusulas WHERE repetitivas ou filtros de tratamento de erro. Com essa divisão, garante-se matematicamente que COUNT(approved_trips) + COUNT(rejected_trips) = COUNT(stg_yellow_trips), assegurando 100% de auditabilidade e integridade no pipeline.

## 2026-07-27 — Construção física do modelo dimensional (LED-27 a LED-30)

`model/dims/*.sql` e `model/facts/01_fato_corrida.sql` implementam o que `docs/modelagem_dimensional.md` havia só desenhado. Três decisões não estavam explícitas no doc de modelagem e precisaram de critério próprio, registradas aqui para não ficarem implícitas no código:

1. **`dim_hora.faixa_pico` é derivada por evidência, não por suposição de rush hour.** Calculada como as horas cujo volume de corridas em `approved_trips` fica no percentil 75 ou acima (mesmo princípio de `docs/regras_limpeza.md`: regra nasce do perfilamento). No dado de jan/2024, isso caiu nas horas 14–19.
2. **`dim_atributos_corrida` grava o valor reservado na coluna de atributo, não na chave.** O `NULL` das 140.114 linhas Flex Fare vira `ratecode_id = -1` e `store_and_fwd_flag = 'N/A'` — nenhum dos dois existe no domínio da fonte. Sem isso, um filtro corriqueiro como `WHERE ratecode_id <> 99` descartaria essas linhas junto com as de código 99, porque `NULL <> 99` não é verdadeiro, e o número sairia errado sem dar erro. O valor reservado não vira chave substituta porque um `id_atributos_sk = -1` universal teria de representar as combinações de nulos dos 3 vendors ao mesmo tempo e o `vendor_id` se perderia; cada combinação observada (25 no total) mantém linha própria com chave sequencial. "Desconhecido" dispensa valor reservado: `RatecodeID = 99` já é o código da própria fonte.
3. **`is_speed_outlier` entra em `fato_corrida`** mesmo a tabela-síntese §4.3 de `docs/modelagem_dimensional.md` não listando-a — `docs/regras_limpeza.md` item 5 pede essa flag explicitamente na fato, e nenhum dos dois documentos justifica excluí-la; tratado como lacuna do doc de modelagem, não como decisão de omitir.

Validado rodando o pipeline duas vezes: `fato_corrida` produz sempre 2.964.553 linhas com os mesmos `id_corrida_sk` (idempotente, LED-35), e a reconciliação bate exata — `SUM(total_amount)` de `raw_trips` menos `fato_corrida` é 2.228,31, igual à soma de `rejected_trips.total_amount` (LED-34). Nenhum FK da fato ficou nulo.