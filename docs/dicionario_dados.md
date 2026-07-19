# Dicionário de dados — Yellow Taxi Trip Records

Fonte oficial: [NYC TLC — Data Dictionary, Yellow Taxi Trip Records](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf) (versão de 18/03/2025). Cópia local em `docs/data_dictionary_trip_records_yellow.pdf`.

Esta tabela documenta o significado de cada campo de `raw_trips`, traduzido e organizado para uso nas etapas de perfilamento (LED-14 a LED-18) e tratamento (LED-19 a LED-25). Todo campo abaixo existe hoje em `raw_trips`, exceto onde indicado.

| Campo | Tipo em `raw_trips` | Descrição | Valores / domínio |
|---|---|---|---|
| `VendorID` | INTEGER | Código do provedor TPEP que forneceu o registro. | Segundo o dicionário (vigente em 2025): 1 = Creative Mobile Technologies, LLC · 2 = Curb Mobility, LLC · 6 = Myle Technologies Inc · 7 = Helix. **Atenção:** essa lista é da versão de mar/2025; para dados de jan/2024 o TLC usava outra lista (ex.: 1 = Creative Mobile Technologies, 2 = VeriFone Inc). Validar os valores distintos reais em `raw_trips` no perfilamento (LED-15) antes de assumir esse mapeamento. |
| `tpep_pickup_datetime` | TIMESTAMP | Data e hora em que o taxímetro foi acionado (início da corrida). | — |
| `tpep_dropoff_datetime` | TIMESTAMP | Data e hora em que o taxímetro foi desligado (fim da corrida). | — |
| `passenger_count` | BIGINT | Número de passageiros no veículo. Campo preenchido pelo motorista. | — |
| `trip_distance` | DOUBLE | Distância percorrida da corrida, em milhas, reportada pelo taxímetro. | — |
| `RatecodeID` | BIGINT | Código de tarifa final vigente ao fim da corrida. | 1 = Standard rate · 2 = JFK · 3 = Newark · 4 = Nassau ou Westchester · 5 = Negotiated fare · 6 = Group ride · 99 = Null/unknown |
| `store_and_fwd_flag` | VARCHAR | Indica se o registro ficou retido na memória do veículo antes de ser enviado ao provedor, por falta de conexão ("store and forward"). | Y = sim (retido e reenviado) · N = não |
| `PULocationID` | INTEGER | Zona de táxi (TLC Taxi Zone) em que o taxímetro foi acionado (origem). Chave para `raw_zone_lookup.LocationID`. | 1–265 |
| `DOLocationID` | INTEGER | Zona de táxi em que o taxímetro foi desligado (destino). Chave para `raw_zone_lookup.LocationID`. | 1–265 |
| `payment_type` | BIGINT | Forma de pagamento da corrida. | 0 = Flex Fare trip · 1 = Credit card · 2 = Cash · 3 = No charge · 4 = Dispute · 5 = Unknown · 6 = Voided trip |
| `fare_amount` | DOUBLE | Tarifa calculada pelo taxímetro com base em tempo e distância. | — |
| `extra` | DOUBLE | Extras e sobretaxas diversas. | — |
| `mta_tax` | DOUBLE | Taxa acionada automaticamente com base na tarifa medida em uso. | — |
| `tip_amount` | DOUBLE | Valor da gorjeta. Preenchido automaticamente só para pagamentos em cartão; gorjetas em dinheiro não entram aqui. | — |
| `tolls_amount` | DOUBLE | Total de pedágios pagos na corrida. | — |
| `improvement_surcharge` | DOUBLE | Sobretaxa de melhoria cobrada por corrida, em vigor desde 2015. | — |
| `total_amount` | DOUBLE | Valor total cobrado do passageiro. Não inclui gorjetas em dinheiro. | — |
| `congestion_surcharge` | DOUBLE | Valor total cobrado referente à sobretaxa de congestionamento do estado de NY (NYS congestion surcharge). | — |
| `Airport_fee` | DOUBLE | Taxa aplicada apenas em embarques nos aeroportos LaGuardia e JFK. | — |
| `cbd_congestion_fee` | *(não presente)* | Cobrança por corrida da zona de "Congestion Relief" da MTA, em vigor desde 05/01/2025. | — não se aplica a jan/2024, coerente com a ausência do campo em `raw_trips` |

## Dicionário — Taxi Zone Lookup (`raw_zone_lookup`)

Fonte: [TLC Taxi Zone Lookup Table](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv). Tipos e domínios conferidos via `DESCRIBE` no schema real.

| Campo | Tipo em `raw_zone_lookup` | Descrição | Valores / domínio |
|---|---|---|---|
| `LocationID` | BIGINT | Identificador único da zona de táxi. Chave para `PULocationID`/`DOLocationID` de `raw_trips`. | 1–265 |
| `Borough` | VARCHAR | Distrito de NY em que a zona está localizada. | `Bronx` · `Brooklyn` · `EWR` · `Manhattan` · `N/A` · `Queens` · `Staten Island` · `Unknown`. `N/A` e `Unknown` são texto literal, não NULL. |
| `Zone` | VARCHAR | Nome descritivo da zona. | 265 valores distintos, ~1:1 com `LocationID`. |
| `service_zone` | VARCHAR | Categoria de área de serviço da zona. | `Airports` · `Boro Zone` · `EWR` · `N/A` · `Yellow Zone`. `N/A` também é texto literal. |


## Colunas técnicas adicionadas na carga (não fazem parte da fonte)

| Campo | Descrição |
|---|---|
| `_loaded_at` | Timestamp de quando a linha foi carregada em `raw_trips`/`raw_zone_lookup`. |
| `_source_file` | Nome do arquivo de origem. |

Ver justificativa em [`docs/decisoes.md`](decisoes.md).

## Pendências para o perfilamento (LED-14 a LED-18)

- Confirmar os valores distintos reais de `VendorID` em `raw_trips` — a lista do dicionário é de 2025 e pode não bater com jan/2024.
- `RatecodeID = 99` ("Null/unknown") e `payment_type = 5` ("Unknown") já são categorias válidas de origem, não erros — não devem ser tratados como nulo/inválido sem critério.
- Verificar se `tip_amount` de corridas pagas em dinheiro está de fato zerado (esperado pela definição do campo) ou se há inconsistência.
