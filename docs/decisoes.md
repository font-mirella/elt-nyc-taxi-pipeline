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
