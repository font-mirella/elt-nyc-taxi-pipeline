# Decisões do projeto

Registro das decisões não óbvias tomadas ao longo do desafio, com a justificativa, para o time todo (assíncrono) entender o porquê sem precisar perguntar.

## 2026-07-18 — DuckDB roda via Docker Compose

Em vez de exigir instalação local do DuckDB CLI, o `Dockerfile`/`docker-compose.yml` sobem um container com a versão exata pinada (`DUCKDB_VERSION` no `Dockerfile`). Garante que os 5 integrantes e a LED, ao reproduzir o pipeline, usem a mesma versão do banco — evita divergência de comportamento entre versões do DuckDB.

## 2026-07-18 — Arquivos de dados brutos não versionados no Git

`raw/data/` (parquet ~48MB + CSV) está no `.gitignore`. Repositório fica leve e sem depender de Git LFS (que exigiria instalação extra por parte de quem clonar, inclusive a LED). Em troca, buscar os arquivos deixa de ser 100% automático: o README documenta os links diretos e o caminho local esperado, e é um passo manual antes de rodar `docker compose run`.

## 2026-07-18 — Colunas de linhagem `_loaded_at` e `_source_file` na camada raw

As tabelas `raw_trips` e `raw_zone_lookup` recebem duas colunas extras além das originais: `_loaded_at` (timestamp da carga) e `_source_file` (nome do arquivo de origem). São puramente aditivas — nenhuma coluna original é renomeada, convertida ou removida — então não violam o princípio de a camada bruta ser fiel à fonte. Servem só para auditoria/rastreabilidade.
