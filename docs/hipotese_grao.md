## Hipótese Inicial de Granularidade — Tabela Fato

> **Projeto:** ELT Taxi NY — LED (Liga Acadêmica de Engenharia de Dados / UFPE)
> **Fonte:** NYC Yellow Taxi Trip Records — janeiro/2024
> **Etapa:** proposta inicial de grão, a partir do perfilamento

---

## 1. Visão Geral

| Item | Descrição |
|---|---|
| **Fonte** | `raw_trips` (2.964.624 corridas) + `raw_zone_lookup` (265 zonas) |
| **Período** | Janeiro/2024 |
| **Modelo alvo** | Esquema Estrela (Star Schema) |
| **Objetivo desta etapa** | Definir o que **uma linha da tabela fato representa** e esboçar as dimensões, com base nas evidências do perfilamento |

---

## 2. Grão proposto

> **Grão:** cada linha da tabela fato representa **uma corrida individual de táxi** — um
> evento de taxímetro completo, do acionamento (`tpep_pickup_datetime`) ao desligamento
> (`tpep_dropoff_datetime`).

Descer mais (ex.: por segmento de trajeto) é impossível — a fonte não fornece essa
granularidade. Subir mais (ex.: agregar por zona/hora) limitaria as análises de tempo,
geografia, financeiro e operação que o projeto precisa responder.

---

## 3. Justificativa (ancorada no perfilamento)

**1. A base já está no grão de corrida — não há duplicatas.** Comparando o total de linhas
com o total de linhas distintas considerando **todas as 19 colunas de negócio**, o resultado
é **2.964.624 = 2.964.624 → zero duplicatas**. Cada registro já é uma corrida única; nenhuma
deduplicação é necessária no staging.

**2. A chave natural é composta e impraticável como PK.** O mesmo teste do item 1 mostra que a combinação das **19 colunas de negócio é única** — existe chave natural, mas ela é inviável na prática: 19 colunas de tipos mistos, que teriam de ser replicadas em cada FK e comparadas em cada join. A fato recebe uma **surrogate key** (`id_corrida_sk`) gerada no staging.

A geração da surrogate é **determinística**, para atender a exigência de idempotência do
pipeline (`CREATE OR REPLACE`): a fato precisa ser reconstruível com as mesmas chaves a cada
execução. Usa-se um hash sobre as 19 colunas da chave natural (`md5`/`hash`), estável a
reordenações da fonte.

**3. Eventos de estorno ocupam linhas próprias.** Valores negativos em campos monetários
concentram-se em `payment_type` 3 (No charge) e 4 (Dispute) — são reversões de cobrança.
Cada estorno é uma linha separada, tratada como corrida com flag `is_estorno`.

---

## 4. Nota sobre o desenho das dimensões

Diferente de bases descritivas, **este dataset é predominantemente de medidas** — distância, contagem de
passageiros e ~11 valores monetários. Os atributos categóricos descritivos são poucos e,
em sua maioria, **códigos isolados de baixa cardinalidade** (`VendorID`, `RatecodeID`,
`store_and_fwd_flag`, `payment_type`).

Criar uma dimensão de uma coluna para cada um seria ruim. As dimensões naturalmente
"ricas" aqui são as de tempo (**`dim_data`**/**`dim_hora`**) e **`dim_zona`**.
Para os códigos pequenos, a
técnica adequada (Kimball) é uma **junk dimension** — uma única dimensão que consolida os
códigos, com cardinalidade minúscula.

`payment_type` é a exceção e ganha dimensão própria (**`dim_pagamento`**), fora da junk. Dos
quatro códigos, é o único com peso analítico próprio: governa a semântica da gorjeta
(`tip_amount` só é preenchido para cartão), é a causa do grupo de nulos conjunto
(`payment_type = 0`, Flex Fare — §8.1) e é eixo de análise financeira por si só. `VendorID`,
`RatecodeID` e `store_and_fwd_flag` são metadados operacionais sem uso analítico isolado e
permanecem consolidados na junk.

---

## 5. Esboço do Star Schema

```
         ┌─────────────────┐              ┌─────────────────┐
         │    dim_data     │              │    dim_hora     │
         │ PK: id_data_sk  │              │ PK: id_hora_sk  │
         └────────┬────────┘              └────────┬────────┘
                  │ (2 papéis:                     │ (2 papéis:
                  │  embarque / desembarque)       │  embarque / desembarque)
                  └───────────────┐   ┌────────────┘
                                  │   │
 ┌───────────────┐          ┌─────┴───┴─────┐          ┌───────────────────────┐
 │   dim_zona    │          │ fato_corrida  │          │ dim_atributos_corrida │
 │ PK: id_zona_sk│◄─────────┤    (Fato)     ├─────────►│  PK: id_atributos_sk  │
 └───────────────┘  2 papéis└───────┬───────┘          │  (junk dimension)     │
                                    │                  └───────────────────────┘
                                    ▼
                          ┌────────────────────┐
                          │   dim_pagamento    │
                          │ PK: id_pagamento_sk│
                          └────────────────────┘

    FKs em fato_corrida:
      id_data_embarque_sk     → dim_data    (papel: embarque)
      id_data_desembarque_sk  → dim_data    (papel: desembarque)   ← mesma dim, 2 papéis
      id_hora_embarque_sk     → dim_hora    (papel: embarque)
      id_hora_desembarque_sk  → dim_hora    (papel: desembarque)   ← mesma dim, 2 papéis
      id_zona_pu_sk           → dim_zona    (papel: embarque)
      id_zona_do_sk           → dim_zona    (papel: desembarque)   ← mesma dim, 2 papéis
      id_pagamento_sk         → dim_pagamento
      id_atributos_sk         → dim_atributos_corrida
```

A corrida é um evento com **dois instantes** — acionamento e desligamento do taxímetro — e os
dois são chaveados. Chavear apenas o embarque impediria responder perguntas sobre o término
("quantas corridas terminaram na madrugada?", "qual zona recebe mais desembarques no pico?") e
impediria derivar duração a partir das dimensões. É o mesmo mecanismo de role-playing aplicado
a `dim_zona` (PU/DO), estendido ao eixo temporal.

---

## 6. Tabela fato — `fato_corrida`

> Cada linha = uma corrida. As **medidas** (valores numéricos) e as **flags de qualidade**
> ficam aqui; os atributos descritivos são resolvidos por JOIN com as dimensões.

**Medidas:**

| Campo | Origem | Descrição |
|---|---|---|
| `trip_distance` | `trip_distance` | Distância em milhas |
| `passenger_count` | `passenger_count` | Nº de passageiros |
| `trip_duration_minutes` | derivada (`dropoff − pickup`) | Duração da corrida em minutos |
| `fare_amount` | `fare_amount` | Tarifa do taxímetro |
| `extra` | `extra` | Sobretaxas diversas |
| `mta_tax` | `mta_tax` | Taxa estadual MTA |
| `tip_amount` | `tip_amount` | Gorjeta (só cartão) |
| `tolls_amount` | `tolls_amount` | Pedágios |
| `improvement_surcharge` | `improvement_surcharge` | Sobretaxa de acessibilidade |
| `congestion_surcharge` | `congestion_surcharge` | Sobretaxa de congestionamento |
| `Airport_fee` | `Airport_fee` | Taxa de aeroporto (embarque LGA/JFK) |
| `total_amount` | `total_amount` | Valor total cobrado — ver §8.11 |

Todas somam corretamente em qualquer recorte. Razões derivadas (velocidade, percentual de
gorjeta, preço por milha) ficam fora da fato — ver `modelagem_dimensional.md` §3.5.

**Dimensões degeneradas (§8.13):**

| Campo | Descrição |
|---|---|
| `pickup_datetime` | Timestamp bruto do embarque — precisão de segundo, que `dim_data`/`dim_hora` não carregam |
| `dropoff_datetime` | Timestamp bruto do desembarque — idem |

**Chaves e flags de qualidade:**

| Campo | Descrição |
|---|---|
| `id_corrida_sk` | Surrogate key determinística (ver §3.2) |
| `id_data_embarque_sk` / `id_data_desembarque_sk` | FK → `dim_data` (2 papéis) |
| `id_hora_embarque_sk` / `id_hora_desembarque_sk` | FK → `dim_hora` (2 papéis) |
| `id_zona_pu_sk` / `id_zona_do_sk` | FK → `dim_zona` (embarque / desembarque) |
| `id_pagamento_sk` | FK → `dim_pagamento` |
| `id_atributos_sk` | FK → `dim_atributos_corrida` (junk) |
| `is_estorno` | Linha de estorno (valor monetário negativo) — ver §8.2 |
| `is_tip_outlier` | Gorjeta atípica (`tip > 50` ou `% > 100`) — ver §8.3 |
| `is_distance_outlier` | Distância improvável — ver §8.4 |
| `is_fare_outlier` | Tarifa no teto de sistema (`fare_amount`/`total_amount` em 5000/2500 exatos) — ver §8.12 |
| `is_aeroporto` | `COALESCE(Airport_fee, 0) > 0` — ver §8.8 |

As cinco flags são funções determinísticas de medidas que já estão na fato, e nesse sentido
são redundantes: todas poderiam ser recalculadas em tempo de consulta. Elas são materializadas
para **congelar a definição**, não por desempenho. Cada limiar (`> 50 mi` OU `dist/fare > 5`;
`tip > 50` OU `tip > fare`) foi decidido com evidência quantificada e revisada; se cada consulta
reescrever o `CASE`, a definição diverge entre analistas e os números deixam de ser comparáveis.
A flag é o contrato da regra de qualidade.

---

## 7. Dimensões candidatas

| Dimensão | Grão | Origem |
|---|---|---|
| `dim_data` | 1 linha por dia | `tpep_pickup_datetime` / `tpep_dropoff_datetime` (parte data) |
| `dim_hora` | 1 linha por hora do dia | `tpep_*_datetime` (parte hora) |
| `dim_zona` | 1 linha por zona TLC | `raw_zone_lookup` |
| `dim_pagamento` | 1 linha por código | `payment_type` |
| `dim_atributos_corrida` (junk) | 1 linha por combinação | `VendorID`, `RatecodeID`, `store_and_fwd_flag` |


**`dim_data`** cobre de **2024-01-01 a 2024-02-02** — o intervalo de embarque **e** desembarque,
não só o de embarque. 600 corridas legítimas começam em janeiro e terminam em fevereiro;
construir a dimensão a partir de `DISTINCT date(pickup)` deixaria `id_data_desembarque_sk` sem
correspondência nessas linhas. Atributos: dia, mês, dia da semana e fim de semana. Feriado fica
como melhoria futura — depende de definir a fonte do calendário (federal norte-americano,
municipal de NYC, ou ambos), decisão que não bloqueia a entrega.

**`dim_hora`** tem grão de **hora** (24 linhas). As perguntas de negócio em escopo — turno,
horário de pico, distribuição ao longo do dia — são todas de nível hora, e a precisão de segundo
permanece disponível nos timestamps degenerados da fato para análises mais finas. Atributos:
hora, turno (madrugada/manhã/tarde/noite), faixa de pico.

**`dim_zona`** tem `LocationID` como chave natural. O nome da zona não serve: são **262 nomes
distintos para 265 IDs** — `Governor's Island/Ellis Island/Liberty Island` cobre 103, 104 e 105,
e `Corona` cobre 56 e 57. Chavear por `Zone` colapsaria zonas distintas e produziria fan-out no
join com a fato.

**`dim_pagamento`** contém os 7 códigos do dicionário, não os 5 observados. Os códigos 5
(Unknown) e 6 (Voided) não ocorrem em jan/2024 mas entram na dimensão mesmo assim, para que um
período futuro com esses códigos não quebre o join.

---

## 8. Considerações que impactam a modelagem

Varredura de **todo o perfilamento**. Cada achado abaixo vira uma flag na fato, uma regra de
dimensão, ou uma decisão de staging a documentar.

### 8.1 Grupo de nulos conjunto (`payment_type = 0`, 140.162 linhas)
5 colunas ficam nulas em bloco (`passenger_count`, `RatecodeID`, `store_and_fwd_flag`,
`congestion_surcharge`, `Airport_fee`), sempre nas mesmas linhas, todas de Flex Fare trip.
As medidas seguem `NULL` e os atributos categóricos mapeiam para um membro
**"Não se aplica (Flex Fare)"**, distinto do membro **"Desconhecido"** usado para
`RatecodeID = 99`. Os dois membros são criados explicitamente nas dimensões: sem eles, o join da
fato não encontra correspondência para as 140.162 linhas.

### 8.2 Estornos (valores monetários negativos)
Concentrados em `payment_type` 3 e 4. Aparecem em `fare_amount` (37.448), `extra` (17.548),
`mta_tax`, `improvement_surcharge` (35.500) e `congestion_surcharge` — em padrão conjunto.
**Fato:** flag `is_estorno`; não excluir (preserva o dado financeiro).

### 8.3 Gorjetas atípicas (`tip_amount`)
Outliers com `fare_amount = 0.01` e gorjeta alta (lançamento avulso na maquininha) e casos de
gorjeta desproporcional à tarifa. **Fato:** flag `is_tip_outlier` (`tip > 50` ou `% > 100`).

### 8.4 Distância improvável (`trip_distance`)
819 corridas (0,03%): `> 50 mi` OU razão `dist/fare > 5`. As de razão alta são curtas
(mediana 17 min) no mesmo borough → erro de GPS/taxímetro. **Fato:** flag `is_distance_outlier`.

### 8.5 Distância zero (`trip_distance = 0`, 60.371 linhas)
Esperada em `RatecodeID` 5 e 6 (negociada/grupo). Anômala em `RatecodeID = 1` (Standard,
~22 mil), com correlação fraca entre duração e tarifa. Mantida sem flag dedicada nesta etapa —
não há critério de outlier claro o suficiente para congelar um limiar.

### 8.6 passenger_count
Não se aplica filtro para remover `passenger_count > 4` (vans/SUV são legítimas). O NULL
(parte do grupo 8.1) permanece `NULL` na fato — não vira `0`, que já é valor observado e válido.

### 8.7 Datas inválidas (`tpep_*_datetime`)
18 corridas com pickup fora de janeiro/2024 e 56 com dropoff antes do pickup — 74 linhas ao
todo — são excluídas no staging, com registro em `rejected_records`, antes de montar
`dim_data`/`dim_hora`. Volume desprezível.

Há ainda **814 corridas com `dropoff = pickup`** (duração exatamente zero) que o filtro `<` não
alcança. Impacto direto na modelagem: `trip_duration_minutes` fica em 0 e qualquer razão que use
duração como denominador divide por zero. Decisão pendente: excluí-las junto com as 74, ou
mantê-las e proteger as consultas de velocidade com `NULLIF(SUM(trip_duration_minutes), 0)`. 

### 8.8 Critério de "corrida de aeroporto"
O critério é `COALESCE(Airport_fee, 0) > 0`, não `service_zone = 'Airports'`: ~10,9 mil corridas
de aeroporto (ex.: East Elmhurst, bairro do LaGuardia) ficam fora da zona `Airports`.

`is_aeroporto` é atributo da fato, não de `dim_zona`. O critério depende de `Airport_fee`, que é
propriedade da corrida — a mesma zona tem corridas com e sem a taxa. Como atributo dimensional,
variaria por linha da fato, o que contraria a definição de dimensão.

### 8.9 `"N/A"`/`"Unknown"` como texto literal em `raw_zone_lookup`
Aparecem em `Borough`, `service_zone` e `Zone` como **texto**, não `NULL`. **dim_zona:**
normalizar explicitamente ao montar a dimensão (um filtro `IS NULL` não os captura).

### 8.10 Limitação geográfica do `congestion_surcharge`
`raw_zone_lookup` não distingue a fronteira exata da zona de congestionamento (abaixo da 96th
St) dentro de Manhattan. Análises que dependam disso terão precisão apenas por borough — a
`dim_zona` não resolve o nível de rua.

### 8.11 Reconciliação de `total_amount`
74,3% das linhas reconciliam exato com a soma dos componentes; nas demais a divergência é pequena
e estruturada (mediana −$2,50 = `congestion_surcharge`).

`total_amount` aparenta ser redundante com as outras 8 medidas monetárias, mas **não é
derivável**: em 25,7% das linhas a soma não fecha. É o valor que a fonte declara ter sido
efetivamente cobrado, com autoridade que uma soma recalculada não teria. Permanece na fato como
medida da fonte, sem recomputação.

### 8.12 Teto de sistema em `fare_amount` / `total_amount`
Valores máximos concentrados em números redondos (5000.0 e 2500.0 exatos, repetidos) indicam
teto de sistema, não tarifas reais. **Fato:** flag `is_fare_outlier` — marcar, não excluir.

### 8.13 Dimensão degenerada
Não há dimensão degenerada clássica nesta fonte. Uma dimensão degenerada é um identificador de
transação mantido na fato sem tabela própria (nº de nota fiscal, nº de cupom, nº de pedido), e
esta base não tem trip ID nem identificador de motorista ou veículo (§3.2).

Os **timestamps brutos** (`pickup_datetime`, `dropoff_datetime`) exercem papel equivalente:
permanecem na fato por carregarem precisão de segundo que `dim_data` (dia) e `dim_hora` (hora)
não representam, e não geram dimensão própria porque teriam cardinalidade próxima à da fato.
São classificados como degenerados em §6.

---

## 9. Referências

- **NYC TLC** — Yellow Taxi Trip Records e Data Dictionary.
- **Kimball, Ralph & Ross, Margy.** *The Data Warehouse Toolkit.* 3rd ed. Wiley, 2013 —
  grão da tabela fato, surrogate key, dimensões degeneradas, **junk dimensions**,
  **role-playing dimensions** e aditividade de medidas.

---

*Hipótese inicial. As decisões finais do modelo estão em `modelagem_dimensional.md`.*
