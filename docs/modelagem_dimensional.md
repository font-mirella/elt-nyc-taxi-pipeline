# Modelagem Dimensional — definição do star schema (LED-26, LED-31 a LED-33)

> **Projeto:** ELT Taxi NY — LED (Liga Acadêmica de Engenharia de Dados / UFPE)
> **Fonte:** `staging_trips` + `staging_zone_lookup` (jan/2024)
> **Status:** documento normativo do modelo. A partir daqui, decisões de modelagem são
> alteradas aqui — [`docs/hipotese_grao.md`](hipotese_grao.md) fica como registro da etapa de
> perfilamento. Evidência quantitativa em [`docs/perfilamento_notas.md`](perfilamento_notas.md).

---

## 1. Grão da tabela fato (LED-26)

> **Uma linha de `fato_corrida` representa uma corrida individual de táxi** — um evento de
> taxímetro completo, do acionamento (`pickup_datetime`) ao desligamento (`dropoff_datetime`),
> que passou pelas regras de limpeza da camada de staging.

Três consequências do grão, que valem como critério de aceite:

1. **Contagem.** `COUNT(*)` sobre a fato = corridas aprovadas no staging. Nenhuma linha da fato
   agrega mais de uma corrida, e nenhuma corrida aprovada aparece em mais de uma linha.
2. **Escopo.** As corridas com pickup fora de janeiro/2024 e as com dropoff anterior ao pickup
   não entram na fato. Elas permanecem rastreáveis na tabela de
   registros rejeitados da staging, com o motivo da exclusão.
3. **Estornos entram.** Corridas com valores monetários negativos (`payment_type` 3 e 4) são
   eventos reais de reversão de cobrança e ocupam linha própria na fato, marcadas com
   `is_estorno`. Não são deduzidas de outras linhas nem excluídas.

O grão não pode descer — a fonte não fornece segmentos de trajeto — e não deve subir: agregar
por zona/hora na própria fato inviabilizaria as análises de tempo, geografia, financeiro e
operação previstas no desafio.

---

## 2. Chaves: naturais e substitutas (LED-31)

### 2.1 `fato_corrida`

**Chave natural:** existe, e é a combinação das 19 colunas de negócio. O perfilamento provou a
unicidade dessa combinação (2.964.624 linhas = 2.964.624 distintas, zero duplicatas).

**Decisão: surrogate key `id_corrida_sk`.** A chave natural é impraticável como PK — 19 colunas
de tipos mistos, que teriam de ser replicadas em cada relacionamento e
comparadas em cada join.

**Geração determinística.** O pipeline precisa ser idempotente (`CREATE OR REPLACE`): duas
execuções sobre a mesma fonte produzem a mesma fato, com as mesmas chaves. Usa-se um
`hash`/`md5` sobre as 19 colunas — a mesma corrida recebe sempre a mesma chave,
independentemente da ordem de leitura ou das demais linhas.

### 2.2 Dimensões

| Dimensão | Chave natural | Chave substituta | Justificativa |
|---|---|---|---|
| `dim_data` | a própria data | `id_data_sk` (`AAAAMMDD`, ex. `20240115`) | Chave inteligente: legível em depuração, ordenável, e a prática consagrada para dimensões de data |
| `dim_hora` | a hora do dia (0–23) | `id_hora_sk` (0–23) | Domínio fechado e estável; chave substituta coincide com o valor natural |
| `dim_zona` | `location_id` | `id_zona_sk` | Chave natural íntegra e estável (ver 2.3), mas isolada da fonte por convenção do modelo |
| `dim_pagamento` | `payment_type` | `id_pagamento_sk` | Domínio fechado de 7 códigos do dicionário TLC |
| `dim_atributos_corrida` | a combinação dos 3 códigos | `id_atributos_sk` | Junk dimension: a fonte não tem identificador para essa combinação, então a chave é inteiramente artificial. São 25 combinações observadas |

### 2.3 `dim_zona`: a chave natural é `location_id`

`location_id` é o identificador que a fonte declara como único e é o código que
`pu_location_id`/`do_location_id` carregam na fato — chavear por ele mantém o relacionamento
direto, sem tradução intermediária. Os campos descritivos (`zone`, `borough`) são atributos, não
chave: são rótulos textuais, sujeitos a revisão pela TLC entre versões do arquivo de referência.

### 2.4 Membros obrigatórios de "Desconhecido" e "Não se aplica"

Toda dimensão com atributo proveniente de coluna anulável recebe **dois membros criados
explicitamente**, com chaves reservadas:

| Chave | Membro | Quando se aplica |
|---|---|---|
| `-1` | Não se aplica | Ausência estrutural: as 140.162 linhas de `payment_type = 0` (Flex Fare), em que `RatecodeID` e `store_and_fwd_flag` são nulos por natureza do registro |
| `-2` | Desconhecido | Valor existe mas não é identificável: `RatecodeID = 99` ("Null/unknown" no dicionário) |

Os dois são distintos porque têm causas diferentes: uni-los perderia a informação de que o
registro é Flex Fare. As FKs da fato apontam para esses membros em vez de carregarem `NULL`, o
que preserva a contagem do grão sob `INNER JOIN` — sem eles, as 140.162 linhas do grupo Flex
Fare não encontrariam correspondência na dimensão.

`dim_zona` é exceção: os valores `'N/A'` e `'Unknown'` de `borough`, `zone` e `service_zone` já
chegam normalizados como `'Desconhecido'` pelo `staging_zone_lookup`, então a dimensão não
precisa de membro próprio para eles.

---

## 3. Dimensão degenerada e atributos redundantes (LED-32)

### 3.1 Não há dimensão degenerada clássica

Dimensão degenerada é um identificador de transação mantido na fato sem tabela dimensional
própria. Esta fonte **não possui identificador
de transação**: não há trip ID, nem identificador de motorista, veículo ou licença. A avaliação
se encerra com resultado negativo, e é essa ausência que motiva a surrogate key da seção 2.1.

### 3.2 Os timestamps brutos exercem papel equivalente

`pickup_datetime` e `dropoff_datetime` permanecem na fato como colunas, ao lado das quatro FKs
temporais que deles derivam. A razão é de precisão: `dim_data` tem grão de dia e `dim_hora` grão
de hora, e nenhuma das duas representa minuto e segundo. Cálculos que dependem da precisão
original — duração exata, ordenação de eventos dentro da mesma hora — precisam do valor bruto.

Não geram dimensão própria porque teriam cardinalidade próxima à da fato, o que descaracteriza
uma dimensão. Funcionalmente são atributos degenerados e estão assim classificados.

### 3.3 Redundância avaliada, item a item

Textos e descrições não são copiados para a fato: `borough`, `zone` e `service_zone` vivem em
`dim_zona` e chegam por join. Restam dois casos que merecem justificativa por serem redundâncias
deliberadas.

**`total_amount`** parece derivável dos outros oito componentes monetários, mas não é: a soma
fecha em apenas 74,3% das linhas (§8.11 de `hipotese_grao.md`). É o valor que a fonte declara ter
sido cobrado, com autoridade que um total recalculado não teria. Fica.

**As cinco flags** (`is_estorno`, `is_tip_outlier`, `is_distance_outlier`, `is_fare_outlier`,
`is_aeroporto`) são funções determinísticas de medidas que já estão na fato — poderiam ser
recalculadas a cada consulta. São materializadas assim mesmo, ver §3.4.

### 3.4 Por que flags redundantes são materializadas

Cada flag corresponde a um limiar decidido com evidência quantificada: `is_distance_outlier` usa
`> 50 mi` OU `dist/fare > 5`, derivado dos quantis exatos da distribuição; `is_tip_outlier` usa
`tip > 50` OU `tip > fare`. Recalcular esses `CASE` em cada consulta faria a definição divergir
entre analistas, e números produzidos com limiares diferentes deixariam de ser comparáveis.

A flag materializada é o contrato da regra de qualidade: existe uma única definição, versionada
junto com o modelo. O custo em espaço — cinco booleanos por linha — é irrelevante frente a isso.

### 3.5 `trip_duration_minutes`: a única medida derivada materializada

Duração é derivada de dois campos que já estão na fato (`dropoff_datetime − pickup_datetime`),
então tecnicamente é redundante. Entra como coluna por dois motivos: é **aditiva**, e por isso
soma corretamente em qualquer recorte, e aparece em quase toda consulta de operação — deixá-la
implícita obrigaria a repetir aritmética de timestamp em cada uma.

As outras derivadas possíveis são razões (velocidade, percentual de gorjeta, preço por milha) e
não seguem o mesmo critério: não são aditivas. A média das razões não equivale à razão das
somas, então uma coluna pré-calculada por linha daria resultado errado ao ser agregada. Ficam
para a camada de consumo, onde numerador e denominador — ambos já na fato — são somados antes
da divisão.

---

## 4. Alocação de atributos (LED-33)

Cada coluna disponível ao fim do staging e seu destino no modelo, com a justificativa.

### 4.1 Origem: `staging_trips`

| Coluna | Destino | Papel | Por quê |
|---|---|---|---|
| `vendor_id` | `dim_atributos_corrida` | Atributo | Código operacional de baixa cardinalidade (3 valores observados), sem uso analítico isolado. Consolidado na junk em vez de gerar dimensão de uma coluna |
| `pickup_datetime` | `fato_corrida` | Degenerado + origem de FK | Precisão de segundo que as dimensões temporais não carregam; gera `id_data_embarque_sk` e `id_hora_embarque_sk` |
| `dropoff_datetime` | `fato_corrida` | Degenerado + origem de FK | Idem, para `id_data_desembarque_sk` e `id_hora_desembarque_sk` |
| `passenger_count` | `fato_corrida` | Medida aditiva | Somável ("passageiros transportados") e também usado como chave de agrupamento; cardinalidade 0–9 não justifica dimensão |
| `trip_distance` | `fato_corrida` | Medida aditiva | Quantidade contínua do evento |
| `ratecode_id` | `dim_atributos_corrida` | Atributo | Categórico de baixa cardinalidade (7 valores). Descreve como a tarifa foi calculada, não quanto foi cobrado |
| `store_and_fwd_flag` | `dim_atributos_corrida` | Atributo | Metadado de transmissão (Y/N), sem medida associada |
| `pu_location_id` | `fato_corrida` → `dim_zona` | FK (`id_zona_pu_sk`) | Papel de embarque no role-playing de `dim_zona` |
| `do_location_id` | `fato_corrida` → `dim_zona` | FK (`id_zona_do_sk`) | Papel de desembarque, mesma dimensão |
| `payment_type` | `dim_pagamento` | FK (`id_pagamento_sk`) | Único dos códigos com peso analítico próprio: governa a semântica de `tip_amount` e é a causa do grupo de nulos conjunto. Promovido da junk a dimensão própria |
| `fare_amount` | `fato_corrida` | Medida aditiva | Componente monetário |
| `extra` | `fato_corrida` | Medida aditiva | Componente monetário |
| `mta_tax` | `fato_corrida` | Medida aditiva | Componente monetário |
| `tip_amount` | `fato_corrida` | Medida aditiva | Componente monetário |
| `tolls_amount` | `fato_corrida` | Medida aditiva | Componente monetário |
| `improvement_surcharge` | `fato_corrida` | Medida aditiva | Componente monetário |
| `congestion_surcharge` | `fato_corrida` | Medida aditiva | Componente monetário; `NULL` preservado no grupo Flex Fare, não convertido em `0` |
| `airport_fee` | `fato_corrida` | Medida aditiva | Componente monetário; `NULL` preservado, mesma razão |
| `total_amount` | `fato_corrida` | Medida aditiva | Valor cobrado segundo a fonte; não derivável dos componentes (ver 3.3) |
| `_loaded_at` | — | Não propagado | Linhagem da carga; permanece em `raw_trips`/`staging_trips` |
| `_source_file` | — | Não propagado | Idem |

### 4.2 Origem: `staging_zone_lookup`

| Coluna | Destino | Papel | Por quê |
|---|---|---|---|
| `location_id` | `dim_zona` | Chave natural | Identificador declarado único pela fonte; base da FK com a fato |
| `borough` | `dim_zona` | Atributo | Nível geográfico mais alto; eixo de agregação das análises de geografia |
| `zone` | `dim_zona` | Atributo | Nível geográfico mais granular disponível |
| `service_zone` | `dim_zona` | Atributo | Categoria de área de serviço da TLC. Não serve como critério de aeroporto (ver 4.3) |

### 4.3 Atributos derivados

| Atributo | Destino | Justificativa |
|---|---|---|
| `trip_duration_minutes` | `fato_corrida` | Única medida derivada materializada: aditiva e de uso constante |
| `is_estorno` | `fato_corrida` | `fare_amount < 0`. Qualidade da linha, varia por corrida |
| `is_distance_outlier` | `fato_corrida` | Qualidade da linha, limiar congelado (§3.4) |
| `is_tip_outlier` | `fato_corrida` | Qualidade da linha, limiar congelado (§3.4) |
| `is_fare_outlier` | `fato_corrida` | Qualidade da linha: valor no teto de sistema |
| `is_aeroporto` | `fato_corrida` | `COALESCE(airport_fee, 0) > 0`. Não pode ir para `dim_zona`: o critério depende de uma medida da corrida, e a mesma zona tem corridas com e sem a taxa |
| Dia da semana, fim de semana | `dim_data` | Função exclusiva da data |
| Turno, faixa de pico | `dim_hora` | Função exclusiva da hora do dia |

---

## 5. Referências

- **NYC TLC** — Yellow Taxi Trip Records e Data Dictionary.
- **Kimball, Ralph & Ross, Margy.** *The Data Warehouse Toolkit.* 3rd ed. Wiley, 2013 —
  declaração de grão, surrogate keys, dimensões degeneradas, junk dimensions, role-playing,
  aditividade e SCD.
