-- dim_atributos_corrida (LED-29/33): junk dimension consolidando vendor_id + ratecode_id +
-- store_and_fwd_flag — códigos de baixa cardinalidade sem uso analítico isolado
-- (docs/modelagem_dimensional.md §2.2, §4.1). Gerada a partir das combinações reais em
-- approved_trips (25 observadas), não de um produto cartesiano.
--
-- Sobre os membros -1/-2 (docs/modelagem_dimensional.md §2.4): o grupo Flex Fare
-- (ratecode_id/store_and_fwd_flag NULL) ocorre nos 3 vendors (1, 2 e 6) com volumes bem
-- diferentes entre si. Colapsar todos num único id_atributos_sk = -1 universal perderia
-- essa distinção sem necessidade: o requisito de "nunca carregar NULL na FK da fato" já
-- fica satisfeito porque toda combinação observada — inclusive as com atributo nulo —
-- vira uma linha própria com chave substituta normal (a fato nunca precisa de um FK
-- nulo aqui). Por isso ratecode_id NULL e ratecode_id = 99 recebem apenas o rótulo
-- descritivo ("Não se aplica" / "Desconhecido"), sem uma chave reservada separada.
CREATE OR REPLACE TABLE dim_atributos_corrida AS
SELECT
    ROW_NUMBER() OVER (ORDER BY vendor_id, ratecode_id, store_and_fwd_flag) AS id_atributos_sk,
    vendor_id,
    ratecode_id,
    CASE
        WHEN ratecode_id IS NULL THEN 'Não se aplica'
        WHEN ratecode_id = 99 THEN 'Desconhecido'
        WHEN ratecode_id = 1 THEN 'Standard rate'
        WHEN ratecode_id = 2 THEN 'JFK'
        WHEN ratecode_id = 3 THEN 'Newark'
        WHEN ratecode_id = 4 THEN 'Nassau ou Westchester'
        WHEN ratecode_id = 5 THEN 'Negotiated fare'
        WHEN ratecode_id = 6 THEN 'Group ride'
    END AS ratecode_desc,
    store_and_fwd_flag,
    CASE
        WHEN store_and_fwd_flag IS NULL THEN 'Não se aplica'
        WHEN store_and_fwd_flag = 'Y' THEN 'Sim'
        WHEN store_and_fwd_flag = 'N' THEN 'Não'
    END AS store_and_fwd_desc
FROM (SELECT DISTINCT vendor_id, ratecode_id, store_and_fwd_flag FROM approved_trips) combos
ORDER BY vendor_id, ratecode_id, store_and_fwd_flag;
