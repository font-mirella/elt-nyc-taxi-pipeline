-- Verificações do modelo dimensional (LED-34): reconciliação de totais/contagens do
-- modelo final (fato_corrida) contra a camada bruta (raw_trips), explicando qualquer
-- diferença pelas linhas de rejected_trips. error() interrompe run_all.sql se alguma
-- invariante quebrar — mesmo princípio de quality/01_staging_checks.sql.

-- Grão preservado: os joins com dim_zona e dim_atributos_corrida não podem perder nem
-- duplicar linha nenhuma de approved_trips.
SELECT CASE
    WHEN (SELECT COUNT(*) FROM fato_corrida) != (SELECT COUNT(*) FROM approved_trips)
    THEN error('fato_corrida: contagem diverge de approved_trips - join com dim_zona/dim_atributos_corrida perdeu ou duplicou linha')
    ELSE 'ok: COUNT(fato_corrida) = COUNT(approved_trips) = ' || (SELECT COUNT(*) FROM fato_corrida)
END AS check_grao_preservado;

-- Cobertura total: toda linha de raw_trips está ou na fato, ou em rejected_trips - nunca as duas, nunca nenhuma.
SELECT CASE
    WHEN (SELECT COUNT(*) FROM raw_trips) !=
         ((SELECT COUNT(*) FROM fato_corrida) + (SELECT COUNT(*) FROM rejected_trips))
    THEN error('reconciliacao: COUNT(raw_trips) != COUNT(fato_corrida) + COUNT(rejected_trips)')
    ELSE 'ok: COUNT(raw_trips) = COUNT(fato_corrida) + COUNT(rejected_trips) = ' || (SELECT COUNT(*) FROM raw_trips)
END AS check_cobertura_total;

-- Reconciliação financeira: a diferença de total_amount entre raw e fato é explicada
-- inteiramente pelas linhas excluídas (rejected_trips) - não pode haver diferença residual.
SELECT CASE
    WHEN ABS(
        (SELECT SUM(total_amount) FROM raw_trips)
        - (SELECT SUM(total_amount) FROM fato_corrida)
        - (SELECT SUM(total_amount) FROM rejected_trips)
    ) > 0.01
    THEN error('reconciliacao: SUM(total_amount) de raw_trips nao bate com fato_corrida + rejected_trips')
    ELSE 'ok: SUM(total_amount) raw = fato + rejeitados (diferenca <= 0.01)'
END AS check_reconciliacao_financeira;

-- Grão único: cada corrida aprovada gera exatamente uma chave id_corrida_sk, sem colisão de hash.
SELECT CASE
    WHEN (SELECT COUNT(*) FROM fato_corrida) != (SELECT COUNT(DISTINCT id_corrida_sk) FROM fato_corrida)
    THEN error('fato_corrida: id_corrida_sk duplicado - colisao de hash ou linha repetida')
    ELSE 'ok: id_corrida_sk e unico por linha'
END AS check_chave_unica;

-- Integridade referencial: nenhuma FK da fato pode ser NULL (dim_zona/dim_atributos_corrida
-- cobrem 100% das combinações observadas em approved_trips).
SELECT CASE
    WHEN (
        SELECT COUNT(*) FROM fato_corrida
        WHERE id_data_embarque_sk IS NULL OR id_hora_embarque_sk IS NULL
           OR id_data_desembarque_sk IS NULL OR id_hora_desembarque_sk IS NULL
           OR id_zona_pu_sk IS NULL OR id_zona_do_sk IS NULL
           OR id_pagamento_sk IS NULL OR id_atributos_sk IS NULL
    ) > 0
    THEN error('fato_corrida: FK nula encontrada - dimensao nao cobre alguma combinacao de approved_trips')
    ELSE 'ok: nenhuma FK nula em fato_corrida'
END AS check_fks_nao_nulas;
