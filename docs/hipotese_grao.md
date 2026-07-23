## Hipótese Inicial de Granularidade — Tabela Fato 

> **Projeto:** ELT Taxi NY — LED (Liga Acadêmica de Engenharia de Dados / UFPE)
> **Fonte:** NYC Yellow Taxi Trip Records — janeiro/2024
> **Etapa:** proposta inicial de grão, a partir do perfilamento (LED-14 a LED-16)

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

**2. Não existe chave natural única na fonte.** Não há *trip ID*, nem identificador de
motorista ou veículo. A identidade de uma corrida é a própria combinação de seus atributos.
Portanto, a tabela fato receberá uma **surrogate key** (`id_corrida_sk`) gerada no staging.

**3. Eventos de estorno ocupam linhas próprias.** Valores negativos em campos monetários
concentram-se em `payment_type` 3 (No charge) e 4 (Dispute) — são reversões de cobrança.
Cada estorno é uma linha separada. **Decisão de modelagem a registrar:** tratá-los como
corridas (com flag `is_estorno`) ou como ajuste financeiro — recomenda-se marcar, não excluir.

---

## 4. Nota sobre o desenho das dimensões

Diferente de bases descritivas, **este dataset é predominantemente de medidas** — distância, contagem de
passageiros e ~11 valores monetários. Os atributos categóricos descritivos são poucos e,
em sua maioria, **códigos isolados de baixa cardinalidade** (`VendorID`, `RatecodeID`,
`store_and_fwd_flag`, `payment_type`).

Criar uma dimensão de uma coluna para cada um seria ruim. As duas únicas dimensões
naturalmente "ricas" aqui são **`dim_tempo`** e **`dim_zona`**. Para os códigos pequenos, a
técnica adequada (Kimball) é uma **junk dimension** — uma única dimensão que consolida os
códigos, com cardinalidade minúscula (máx. ~210 combinações).

---

## 5. Esboço do Star Schema

```
                    ┌──────────────────────┐
                    │      dim_tempo       │
                    │   PK: id_tempo_sk    │
                    └───────────┬──────────┘
                                │
    ┌───────────────┐   ┌───────┴───────┐   ┌───────────────────────┐
    │   dim_zona    │   │  fato_corrida │   │ dim_atributos_corrida │
    │ PK: id_zona_sk│◄──┤    (Fato)     ├──►│  PK: id_atributos_sk  │
    └───────────────┘   └───────────────┘   │  (junk dimension)     │
                                            └───────────────────────┘

    FKs em fato_corrida:
      id_tempo_sk       → dim_tempo
      id_zona_pu_sk     → dim_zona   (papel: embarque)
      id_zona_do_sk     → dim_zona   (papel: desembarque)   ← mesma dim, 2 papéis
      id_atributos_sk   → dim_atributos_corrida
```

---

## 6. Tabela fato — `fato_corrida`

> Cada linha = uma corrida. As **medidas** (valores numéricos) e as **flags de qualidade**
> ficam aqui; os atributos descritivos são resolvidos por JOIN com as dimensões.

**Medidas:**

| Campo | Origem | Descrição |
|---|---|---|
| `trip_distance` | `trip_distance` | Distância em milhas |
| `passenger_count` | `passenger_count` | Nº de passageiros |
| `fare_amount` | `fare_amount` | Tarifa do taxímetro |
| `extra` | `extra` | Sobretaxas diversas |
| `mta_tax` | `mta_tax` | Taxa estadual MTA |
| `tip_amount` | `tip_amount` | Gorjeta (só cartão) |
| `tolls_amount` | `tolls_amount` | Pedágios |
| `improvement_surcharge` | `improvement_surcharge` | Sobretaxa de acessibilidade |
| `congestion_surcharge` | `congestion_surcharge` | Sobretaxa de congestionamento |
| `Airport_fee` | `Airport_fee` | Taxa de aeroporto (embarque LGA/JFK) |
| `total_amount` | `total_amount` | Valor total cobrado |

**Chaves e flags de qualidade:**

| Campo | Descrição |
|---|---|
| `id_corrida_sk` | Surrogate key (gerada no staging) |
| `id_tempo_sk` | FK → `dim_tempo` |
| `id_zona_pu_sk` / `id_zona_do_sk` | FK → `dim_zona` (embarque / desembarque) |
| `id_atributos_sk` | FK → `dim_atributos_corrida` (junk) |
| `is_estorno` | Linha de estorno (valor monetário negativo) — ver §8.2 |
| `is_tip_outlier` | Gorjeta atípica (`tip > 50` ou `% > 100`) — ver §8.3 |
| `is_distance_outlier` | Distância improvável — ver §8.4 |

---

## 7. Dimensões candidatas

| Dimensão | Origem | Papel |
|---|---|---|
| `dim_tempo` | `tpep_pickup_datetime` | Dia, mês, hora, dia da semana, turno — pré-computados no staging |
| `dim_zona` | `raw_zone_lookup` | Borough, Zone, service_zone (embarque e desembarque) |
| `dim_atributos_corrida` (junk) | `VendorID`, `RatecodeID`, `payment_type`, `store_and_fwd_flag` | Consolida os códigos categóricos de baixa cardinalidade, decodificados |

> **Alternativa:** se o time preferir, `payment_type` e `RatecodeID` podem virar dimensões
> próprias (pequenas, conformadas) em vez de entrar na junk. As duas abordagens são válidas.

---

## 8. Considerações que impactam a modelagem

Varredura de **todo o perfilamento**. Cada achado abaixo vira uma flag
na fato, uma regra de dimensão, ou uma decisão de staging a documentar.

### 8.1 Grupo de nulos conjunto (`payment_type = 0`, 140.162 linhas)
5 colunas ficam nulas em bloco (`passenger_count`, `RatecodeID`, `store_and_fwd_flag`,
`congestion_surcharge`, `Airport_fee`), sempre nas mesmas linhas, todas de Flex Fare trip.
**Staging:** decidir default vs. flag; afeta a `dim_atributos_corrida` (RatecodeID/store_fwd
nulos) e as medidas de sobretaxa.

### 8.2 Estornos (valores monetários negativos)
Concentrados em `payment_type` 3 e 4. Aparecem em `fare_amount` (37.448), `extra` (17.548),
`mta_tax`, `improvement_surcharge` (35.500) e `congestion_surcharge` — em padrão conjunto.
**Fato:** flag `is_estorno`; não excluir (preserva o dado financeiro).

### 8.3 Gorjetas atípicas (`tip_amount`)
Outliers com `fare_amount = 0.01` e gorjeta alta (lançamento avulso na maquininha) e casos
de gorjeta desproporcional à tarifa. **Recomendação registrada no perfilamento:** flag
`is_tip_outlier` (`tip > 50` ou `% > 100`), em vez de deletar — permite ao BI filtrar os
erros sem perder o valor financeiro real.

### 8.4 Distância improvável (`trip_distance`)
819 corridas (0,03%): `> 50 mi` OU razão `dist/fare > 5`. As de razão alta são curtas
(mediana 17 min) no mesmo borough → erro de GPS/taxímetro. **Fato:** flag `is_distance_outlier`.

### 8.5 Distância zero (`trip_distance = 0`, 60.371 linhas)
Esperada em `RatecodeID` 5 e 6 (negociada/grupo). Anômala em `RatecodeID = 1` (Standard,
~22 mil), com correlação fraca entre duração e tarifa. **Staging:** tratar o subgrupo Standard
à parte (marcar/investigar), não descartar em bloco.

### 8.6 passenger_count
**Decisão técnica registrada:** não aplicar filtro para remover `passenger_count > 4` (vans/SUV
são legítimas). O NULL (parte do grupo 8.1) exige decisão de staging: descartar, valor padrão
ou marcar como `Unknown`.

### 8.7 Datas inválidas (`tpep_*_datetime`)
15 corridas fora de jan/2024 + 56 com dropoff antes do pickup. **Staging:** descartar ou marcar
como inválidas **antes** de montar a `dim_tempo`. Volume desprezível (71 linhas).

### 8.8 Critério de "corrida de aeroporto"
O `Airport_fee > 0` é o critério correto — **não** `service_zone = 'Airports'`. ~10,9 mil
corridas de aeroporto (ex.: East Elmhurst, bairro do LaGuardia) ficam fora da zona `Airports`.
**Modelagem:** derivar o atributo de aeroporto a partir de `Airport_fee`, não da zona.

### 8.9 `"N/A"`/`"Unknown"` como texto literal em `raw_zone_lookup`
Aparecem em `Borough`, `service_zone` e `Zone` como **texto**, não `NULL`. **dim_zona:**
normalizar explicitamente ao montar a dimensão (um filtro `IS NULL` não os captura).

### 8.10 Limitação geográfica do `congestion_surcharge`
`raw_zone_lookup` não distingue a fronteira exata da zona de congestionamento (abaixo da 96th
St) dentro de Manhattan. Análises que dependam disso terão precisão apenas por borough — a
`dim_zona` não resolve o nível de rua. Documentar como limitação.

### 8.11 Reconciliação de `total_amount`
74,3% das linhas reconciliam exato com a soma dos componentes; o restante diverge por valores
pequenos e estruturados (mediana −$2,50 = `congestion_surcharge`). Se `total_amount` for
recomputado a partir das medidas na modelagem, revisitar esse tratamento.

### 8.12 Teto de sistema em `fare_amount` / `total_amount`
Valores máximos concentrados em números redondos (5000.0 e 2500.0 exatos, repetidos) sugerem
teto de sistema, não tarifas reais. Considerar ao definir faixas de valor válido no staging.

---

## 9. Referências

- **NYC TLC** — Yellow Taxi Trip Records e Data Dictionary.
- **Kimball, Ralph & Ross, Margy.** *The Data Warehouse Toolkit.* 3rd ed. Wiley, 2013 —
  grão da tabela fato, surrogate key, dimensões degeneradas e **junk dimensions**.

---

*Hipótese inicial — sujeita a refinamento na etapa de modelagem dimensional (LED-19+).*
