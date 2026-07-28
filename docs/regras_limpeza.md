# Regras de limpeza — `raw_trips` → `staging_trips` (LED-19)

Este documento fecha, com uma regra final e justificada, as decisões que o perfilamento
([`docs/perfilamento_notas.md`](perfilamento_notas.md), LED-14 a LED-18) e a hipótese de
grão ([`docs/hipotese_grao.md`](hipotese_grao.md)) deixaram explicitamente em aberto para a
camada de staging. Nenhum número é re-derivado aqui — toda evidência (quantis, contagens,
correlações) já está versionada nesses dois documentos; este arquivo só decide o que fazer
com cada achado.

## Classificação usada

Seguindo a distinção exigida pelo desafio (seção 04, item 2):

- **Ausente** — campo estruturalmente não preenchido para aquele tipo de registro.
- **Desconhecido** — valor existe e é válido, só não é identificável.
- **Incomum** — valor raro/atípico, mas explicável pelo negócio; não é erro.
- **Inválido** — viola uma regra lógica básica ou está fora do escopo do desafio.

Para inválido e incomum, a regra padrão é **nunca excluir silenciosamente**: ou a linha é
mantida com uma flag booleana (permite ao consumo analítico decidir incluir/excluir), ou —
só quando a linha não tem leitura de negócio possível — ela é excluída da fato e registrada
como *rejected record*.

## Decisões (fecham as pendências de `perfilamento_notas.md` e `hipotese_grao.md` §8)

### 1. Datas inválidas — 18 corridas fora de jan/2024 + 56 com dropoff antes do pickup

*(Pendência 1 do perfilamento; §8.7 da hipótese de grão.)*

**Classificação:** Inválido — fora de jan/2024 viola o escopo temporal do desafio; dropoff
antes do pickup viola a física básica do evento. Nenhum dos dois casos tem leitura de
negócio que os explique (diferente dos valores negativos, que têm causa identificada).

**Regra:** **Excluir** as 74 linhas da `staging_trips`/`fato_corrida`, antes de construir
`dim_data`/`dim_hora` (elas não devem influenciar os limites dessas dimensões). Registrar
cada linha excluída, com o motivo (`fora_do_periodo` / `dropoff_antes_pickup`), em
`quality/rejected_records.sql` ou tabela equivalente — nunca um `DELETE` sem rastro.

**Por quê excluir, e não flag:** volume desprezível (0,0025% da base) e, ao contrário dos
estornos, esses casos não representam um evento de negócio real (uma corrida com fim antes
do início não existiu). Manter na fato só criaria interpretação errada se alguém agregar por
`dim_data`/`dim_hora` sem saber filtrar.

### 2. Valores monetários negativos (estorno)

*(Pendência 2 do perfilamento; §8.2 da hipótese de grão.)*

**Achado já registrado:** negativos em `fare_amount` (37.448), `extra` (17.548),
`mta_tax`/`improvement_surcharge` (35.500) e `congestion_surcharge`, concentrados em
`payment_type` 3 (No charge) e 4 (Dispute) — padrão conjunto, consistente com estorno de
cobrança, não erro de captura aleatório.

**Classificação:** Incomum, explicado pelo negócio.

**Regra:** **Manter** a linha. Adicionar `is_estorno BOOLEAN` na `fato_corrida`
(`true` quando `fare_amount < 0`). Consultas de receita/faturamento decidem explicitamente
se somam essas linhas — a staging não decide isso por elas.

### 3. `payment_type` 5 e 6 ausentes em jan/2024

*(Pendência 3 do perfilamento.)*

**Classificação:** Divergência de dicionário, não erro — mesmo padrão do `VendorID`/Helix
(código 7 também ausente).

**Regra:** Documentar a divergência (feito, aqui e em `perfilamento_notas.md`). A dimensão
que decodifica `payment_type` (própria ou junk, ver `hipotese_grao.md` §7) deve prever os
códigos 5 e 6 como valores válidos possíveis, mesmo sem ocorrência neste mês — garante que
uma execução futura com outro período não quebre por código "desconhecido" pela dimensão.

### 4. Distância improvável — 819 corridas (`trip_distance > 50mi` OU `dist/fare > 5`)

*(Pendência 4 do perfilamento; §8.4 da hipótese de grão.)*

**Achado já registrado:** limiar validado com quantis exatos (p99,9 da distância = 29,5mi;
p99,99 = 54,47mi; p99,9 da razão dist/fare = 0,44). Casos de razão alta são corridas curtas
(mediana 17 min) no mesmo borough → indício de erro de GPS/taxímetro, não corrida real de
longa distância.

**Classificação:** Incomum/outlier de captura.

**Regra:** **Manter** a linha; `is_distance_outlier BOOLEAN` na `fato_corrida`, usando
exatamente o limiar já validado (`trip_distance > 50 OR (fare_amount > 0 AND
trip_distance/fare_amount > 5)`). Consultas de distância/velocidade filtram essa flag
explicitamente quando relevante.

### 4b. Distância zero anômala em `RatecodeID = 1` (Standard)

*(§8.5 da hipótese de grão — dentro das 60.371 linhas de `trip_distance = 0`, a maioria é
esperada em `RatecodeID` 5/6, mas ~22 mil em Standard são anômalas.)*

**Reavaliado em LED-23/25**, agora com `trip_duration_minutes` disponível na staging: repeti a
correlação duração×tarifa especificamente para `ratecode_id = 1 AND trip_distance = 0 AND
fare_amount > 0` (19.696 linhas) — `corr(duração, fare_amount) = 0,27`. A correlação continua
fraca (a disponibilidade da duração não era o bloqueio real; a fraqueza do sinal, sim), então
**a decisão não muda**.

**Classificação:** Incomum.

**Regra:** **Manter**, sem flag dedicada nesta entrega — volume relevante (22 mil) mas sem
critério de outlier tão claro quanto os itens acima (correlação fraca entre duração e
tarifa não permite um limiar seguro ainda). Registrado como melhoria futura, não bloqueia a
modelagem atual. **Importante:** essa decisão vale só para `RatecodeID = 1`. Para as demais
tarifas (`RatecodeID` 2, 5, 6 etc.), `trip_distance = 0` com `fare_amount > 0` é o padrão
esperado de tarifa fixa/negociada, não uma anomalia — não deve ser tratado com o mesmo
critério nem quarentenado.

### 5. Refinar detector de distância com velocidade implícita

*(Pendência 5 do perfilamento — melhoria futura, não bloqueante.)*

**Implementado em LED-23/25**, agora que `trip_duration_minutes` está disponível na staging —
a precondição que este item deixava em aberto. Perfilamento da velocidade implícita
(`trip_distance / duração_h`, para viagens com duração e distância > 0, 2.904.141 linhas):
p99 = 37,1mph; **p99,9 = 49,1mph**; p99,99 = 1.605mph (cauda extrema de erro de captura).
Acima de 100mph: 1.024 corridas (0,035%), com duração mediana de 13s e distância mediana de
2,8mi — mesma assinatura do item 4 (corrida curta com erro de GPS/taxímetro, não velocidade
real).

**Classificação:** Incomum/outlier de captura (mesma causa-raiz do item 4).

**Regra:** **Manter** a linha; `is_speed_outlier BOOLEAN` na `fato_corrida`, usando o limiar
`trip_avg_speed_mph > 50` (arredondado a partir do p99,9 validado acima, mesmo método do item
4). Consultas de distância/velocidade filtram essa flag explicitamente quando relevante —
**não excluir**, pelo mesmo motivo do item 4: o erro tem leitura de negócio (captura), não é
"sem leitura de negócio possível" (critério que justificaria exclusão, ver item 1).

### 6. Grupo de nulos conjunto — `payment_type = 0`, 140.162 linhas

*(§8.1 e §8.6 da hipótese de grão.)*

**Achado já registrado:** correspondência total e bidirecional com `payment_type = 0`
(Flex Fare trip) — ausência estrutural, não falha de captura aleatória.

**Classificação:** Ausente estrutural.

**Regra, por coluna:**
- `congestion_surcharge`, `Airport_fee` (medidas monetárias): manter `NULL`. Não virar `0`
  — um `AVG`/`SUM` sobre essas colunas não deve tratar "não se aplica" como "não pagou".
- `RatecodeID`, `store_and_fwd_flag` (atributos categóricos): mapear para um membro
  explícito **"Não se aplica (Flex Fare)"** na dimensão correspondente — distinto do membro
  **"Desconhecido"** usado para `RatecodeID = 99` (item da tabela-síntese do perfilamento).
  Os dois nulos têm causas diferentes e não podem virar a mesma categoria.
- `passenger_count`: mantém `NULL` (não vira `0`, que já é um valor observado e válido —
  reaproveitá-lo geraria ambiguidade entre "zero passageiros informados" e "não se aplica").

### 7. Gorjetas atípicas — 4.213 linhas (`tip > 50` OU `tip > fare_amount`)

*(§8.3 da hipótese de grão.)*

**Classificação:** Incomum — mistura de lançamento avulso na maquininha (593 casos de
`tip > 50`) e possível erro de digitação (3.928 casos de `tip > fare`), mas com valor
financeiro real em ambos.

**Regra:** **Manter**; `is_tip_outlier BOOLEAN` com o limiar já validado no perfilamento.

### 8. Critério de "corrida de aeroporto"

*(§8.8 da hipótese de grão — já resolvido no perfilamento, formalizado aqui como regra de
staging.)*

**Regra:** Atributo derivado `is_aeroporto = COALESCE(Airport_fee, 0) > 0`. Não usar
`service_zone = 'Airports'`, que perde ~10.887 corridas de East Elmhurst (bairro do
LaGuardia fora da zona oficial).

### 9. `"N/A"` / `"Unknown"` como texto literal em `raw_zone_lookup`

*(§8.9 da hipótese de grão.)*

**Classificação:** Desconhecido, mal representado (string ambígua, não `NULL`).

**Regra:** Ao montar `dim_zona`, normalizar explicitamente `'N/A'` e `'Unknown'` (em
`Borough`, `Zone` e `service_zone`) para uma categoria clara de "Desconhecido" — um filtro
`IS NULL` não captura esses casos, então a normalização precisa ser feita por `CASE`/valor
literal, não por tratamento de nulidade.

### 10. Reconciliação de `total_amount`

*(§8.11 da hipótese de grão — 74,3% batem exato com a soma dos componentes; divergência
residual explicada por `congestion_surcharge`.)*

**Classificação:** Incomum, com causa já identificada (efeito do grupo de nulos do item 6).

**Regra:** Manter `total_amount` da fonte como medida da fato nesta entrega — não
recalcular a partir dos componentes. Se a modelagem decidir recompor esse campo depois,
revisitar esta decisão.

### 11. Teto de sistema em `fare_amount` / `total_amount`

*(§8.12 da hipótese de grão — valores máximos concentrados em 5000,0 e 2500,0 exatos.)*

**Classificação:** Incomum/outlier de sistema.

**Regra:** **Manter**; `is_fare_outlier BOOLEAN` para os valores no teto exato.

## Resumo — o que a staging (LED-20 a LED-25) implementa

| # | Achado | Ação |
|---|---|---|
| 1 | Datas inválidas (74 linhas) | **Excluir** da fato + registrar rejected record |
| 2 | Valores monetários negativos | Manter + `is_estorno` |
| 3 | `payment_type` 5/6 ausentes | Documentado; dimensão prevê os códigos |
| 4 | Distância improvável (819) | Manter + `is_distance_outlier` |
| 4b | Distância zero em Standard | Manter, sem flag (reavaliado LED-23/25, correlação continua fraca) |
| 5 | Detector por velocidade | Manter + `is_speed_outlier` (>50mph, implementado LED-23/25) |
| 6 | Nulos ligados a `payment_type=0` | `NULL` mantido nas medidas; membro "Não se aplica" nas dims |
| 7 | Gorjetas atípicas (4.213) | Manter + `is_tip_outlier` |
| 8 | Critério de aeroporto | `is_aeroporto = COALESCE(Airport_fee,0) > 0` |
| 9 | `"N/A"`/`"Unknown"` em zone_lookup | Normalizar explicitamente em `dim_zona` |
| 10 | Reconciliação `total_amount` | Manter valor da fonte, não recalcular |
| 11 | Teto de sistema (5000/2500) | Manter + `is_fare_outlier` |

Evidência completa (quantis, contagens, correlações) em
[`docs/perfilamento_notas.md`](perfilamento_notas.md) e
[`docs/hipotese_grao.md`](hipotese_grao.md). Consultas versionadas em
[`quality/00_raw_checks.sql`](../quality/00_raw_checks.sql).
