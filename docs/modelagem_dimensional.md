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

### 2.4 Como o modelo representa ausência

Duas colunas da fonte chegam vazias em parte das linhas: `RatecodeID` e `store_and_fwd_flag`
são nulos nas 140.162 corridas de `payment_type = 0` (Flex Fare), porque esse tipo de registro
não tem esses códigos. Não é falha de captura — é ausência estrutural.

O modelo não propaga esse `NULL`, por uma razão prática: `NULL` não responde a comparação. Uma
consulta corriqueira como `WHERE ratecode_id <> 99` descartaria as 140.162 linhas junto com as
de código 99, porque `NULL <> 99` não é verdadeiro — e o número sairia errado sem dar erro
nenhum. Daí a regra:

> Nenhuma FK da fato é nula, e nenhuma coluna de atributo das dimensões é nula.

A primeira metade preserva a contagem do grão: sob `INNER JOIN`, uma FK nula faria as 140.162
corridas Flex Fare sumirem. A segunda metade evita o descarte silencioso descrito acima.

Os valores reservados são `-1` para colunas numéricas e `'N/A'` para colunas de texto — nenhum
dos dois existe no domínio da fonte, então não se confundem com dado real. Não há valor
reservado para "desconhecido" porque a fonte já tem o seu: `RatecodeID = 99` ("Null/unknown"
no dicionário TLC).

Onde o valor reservado é gravado depende da dimensão:

- **Dimensão de chave natural única** — a ausência vira um membro próprio, cuja chave
  substituta é o valor reservado, e a FK da fato aponta para ele.
- **`dim_atributos_corrida` (junk)** — o valor reservado vai na **coluna de atributo**, não na
  chave. Um membro `-1` único teria de representar as combinações de nulos dos três vendors ao
  mesmo tempo, e o `vendor_id` se perderia. Cada combinação observada mantém linha própria com
  chave sequencial, e o que muda é o conteúdo: `ratecode_id = -1`, `store_and_fwd_flag = 'N/A'`.

A regra vale para colunas de atributo das dimensões, não para as medidas da fato.
`passenger_count`, `congestion_surcharge` e `airport_fee` são nulas nas mesmas 140.114 linhas
Flex Fare e continuam assim de propósito: `SUM` e `AVG` ignoram `NULL`, enquanto um `0` no
lugar seria lido como "não pagou" e distorceria a média. Valor reservado não serve aqui, porque 
um `-1` numa medida corromperia a soma. Em contrapartida, filtro sobre medida nula descarta essas 
linhas, e o tratamento fica a cargo de cada consulta.

`dim_zona` é exceção: os valores `'N/A'` e `'Unknown'` de `borough`, `zone` e `service_zone` já
chegam normalizados como `'Desconhecido'` pelo `staging_zone_lookup`, então a dimensão não
não precisa de valor reservado próprio.

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

**As seis flags** (`is_estorno`, `is_speed_outlier`, `is_tip_outlier`, `is_distance_outlier`,
`is_fare_outlier`, `is_aeroporto`) são funções determinísticas de medidas que já estão na fato —
poderiam ser recalculadas a cada consulta. São materializadas assim mesmo, ver §3.4.

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
| `is_speed_outlier` | `fato_corrida` | Qualidade da linha, limiar congelado (§3.4): velocidade implícita `> 50 mph`, validada por quantil (p99,9 = 49,1 mph). Regra 5 de `regras_limpeza.md` |
| `is_aeroporto` | `fato_corrida` | `COALESCE(airport_fee, 0) > 0`. Não pode ir para `dim_zona`: o critério depende de uma medida da corrida, e a mesma zona tem corridas com e sem a taxa |
| Dia da semana, fim de semana | `dim_data` | Função exclusiva da data |
| Turno | `dim_hora` | Função exclusiva da hora do dia |
| Faixa de pico | `dim_hora` | Derivada do volume real de corridas por hora. Recalculada a cada carga, portanto depende do período carregado |

---

## 5. Referências

- **NYC TLC** — Yellow Taxi Trip Records e Data Dictionary.
- **Kimball, Ralph & Ross, Margy.** *The Data Warehouse Toolkit.* 3rd ed. Wiley, 2013 —
  declaração de grão, surrogate keys, dimensões degeneradas, junk dimensions, role-playing,
  aditividade e SCD.
