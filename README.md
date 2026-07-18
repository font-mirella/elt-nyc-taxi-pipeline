# ELT para base pública de corridas de táxi em Nova York

Desafio prático da **LED — Liga Acadêmica de Engenharia de Dados (UFPE)**: construir um pipeline **ELT** completo, usando apenas **SQL** sobre **DuckDB**, para os registros públicos do NYC Yellow Taxi (janeiro/2024) — do arquivo bruto até um modelo dimensional (star schema) capaz de responder perguntas analíticas de negócio.

| | |
|---|---|
| **Início** | 13/07/2026 |
| **Entrega** | 28/07/2026 |
| **Board** | [Linear — ELT Taxi NY - LED](https://linear.app/led-project/project/elt-taxi-ny-led-a133e31e6794) |

## Objetivo

Transformar arquivos públicos e brutos (Parquet + CSV) numa base analítica confiável, reprodutível e auditável, seguindo o padrão **ELT** (Extract → Load → Transform): os dados entram no banco como chegaram e só depois são transformados, dentro do próprio ambiente analítico, via SQL.

## Fonte de dados

| Recurso | Uso |
|---|---|
| [Yellow Taxi, Janeiro 2024 (Parquet)](https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet) | Fonte principal de viagens. Carregada sem edição manual. Local: `raw/data/yellow_tripdata_2024-01.parquet`. |
| [Taxi Zone Lookup Table (CSV)](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv) | Tabela de referência para traduzir códigos de localização em zona/borough. Local: `raw/data/taxi_zone_lookup.csv`. |
| [Dicionário de dados, Yellow Taxi](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf) | Referência para o significado de cada campo. PDF salvo em `docs/data_dictionary_trip_records_yellow.pdf`; versão traduzida e cruzada com o schema real em [`docs/dicionario_dados.md`](docs/dicionario_dados.md). |

## Stack

- **DuckDB** (via Docker) — banco analítico embutido, consulta Parquet/CSV diretamente via SQL.
- **SQL** — única linguagem permitida para extração, tratamento e modelagem.
- **GitHub** — versionamento e colaboração.
- **Linear** — gestão de tarefas.
- **Discord** — canal oficial de comunicação com a LED (obrigatório pelo desafio).

## Estrutura do repositório

```
raw/            # scripts de carga do arquivo bruto (fiel à fonte, sem edição manual) + raw/data/ com os arquivos-fonte
staging/        # limpeza, padronização e regras de qualidade, por domínio
model/
  dims/         # uma dimensão por arquivo (dim_tempo, dim_zona, dim_pagamento, ...)
  facts/        # tabela(s) de fato
analytics/      # consultas finais, uma por perspectiva de negócio (tempo, geografia, financeiro, operação)
quality/        # consultas de perfilamento e verificações de qualidade (auditoria)
docs/           # decisões tomadas, alternativas descartadas, papéis da equipe, glossário
Dockerfile / docker-compose.yml  # ambiente DuckDB com versão fixa, sem instalação local
run_all.sql     # reconstrói o pipeline inteiro do zero, na ordem correta
```

## Como reproduzir o pipeline

```bash
# 1. Baixar os arquivos-fonte (ver tabela "Fonte de dados" acima) para:
#    raw/data/yellow_tripdata_2024-01.parquet
#    raw/data/taxi_zone_lookup.csv
# (raw/data/ não é versionado no Git — os arquivos binários ficam só localmente)

# 2. Build da imagem com o DuckDB CLI (versão fixa, ver Dockerfile)
docker compose build

# 3. Rodar o pipeline completo a partir da raiz do projeto
docker compose run --rm duckdb warehouse.duckdb < run_all.sql
```

Não é necessário instalar o DuckDB localmente. Depois do passo 1 (manual, pois os dados brutos não ficam no Git), o pipeline é reconstruído do zero só com os comandos Docker acima, sem nenhuma edição manual dos dados.

## Camadas do pipeline

1. **Extração e carga bruta** — arquivos de origem carregados fielmente, sem correção manual.
2. **Perfilamento** — investigação de tipos, nulos, cardinalidade, duplicidade e valores improváveis; consultas de verificação versionadas em `quality/`.
3. **Tratamento (staging)** — padronização de tipos, nomes e categorias; toda regra de limpeza justificada.
4. **Modelo dimensional (OLAP)** — pelo menos 1 tabela fato e 3 dimensões, com grão explícito e chaves justificadas.
5. **Consumo analítico** — consultas finais sobre o modelo, cobrindo tempo, geografia, financeiro e operação.

## Princípios do desafio

- **ELT, não ETL**: transformação acontece dentro do DuckDB, nunca antes da carga.
- A camada **raw** nunca é substituída silenciosamente por uma versão corrigida.
- Nenhuma edição manual de arquivo (planilha, "limpeza" fora do SQL).
- Toda transformação, exclusão de registro ou regra de qualidade precisa de justificativa documentada e ser reproduzível.
- Uso de LLM permitido apenas como apoio ao aprendizado (tutora), nunca como executora do projeto — ver `docs/`.
- Toda comunicação relevante do projeto passa pelo canal do Discord da LED.

## Equipe

| Integrante | Papel |
|---|---|
| _a definir_ | |
| _a definir_ | |
| _a definir_ | |
| _a definir_ | |
| _a definir_ | |

## Fluxo de trabalho

- 1 branch por tarefa do Linear (`led-XX-descricao`), PR obrigatório antes de mergear em `main`.
- Antes de abrir PR, rodar `run_all.sql` do zero para garantir que o pipeline continua íntegro.
- Decisões relevantes registradas em `docs/decisoes.md`.
