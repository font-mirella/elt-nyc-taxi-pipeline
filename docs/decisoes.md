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
