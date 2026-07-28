-- dim_pagamento (LED-30): dimensão de forma de pagamento. Domínio fechado dos 7 códigos
-- do dicionário TLC (docs/dicionario_dados.md), gerado por lista fixa, não por DISTINCT
-- sobre a fato — regra 3 de docs/regras_limpeza.md exige prever os códigos 5 e 6 mesmo sem
-- ocorrência em jan/2024, para uma execução futura com outro período não quebrar por
-- "desconhecido" na dimensão.
-- Chave substituta coincide com o valor natural: payment_type já é um código fechado e
-- estável do dicionário (mesmo tratamento de dim_hora).
CREATE OR REPLACE TABLE dim_pagamento AS
SELECT * FROM (VALUES
    (0, 'Flex Fare trip'),
    (1, 'Credit card'),
    (2, 'Cash'),
    (3, 'No charge'),
    (4, 'Dispute'),
    (5, 'Unknown'),
    (6, 'Voided trip')
) AS t(id_pagamento_sk, payment_type_desc);
