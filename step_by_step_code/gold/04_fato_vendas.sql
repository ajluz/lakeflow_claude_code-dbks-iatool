CREATE OR REFRESH LIVE TABLE dataslight_dev.gold.fato_venda
TBLPROPERTIES ("quality" = "gold")
AS 
  WITH origem_fato_venda (
        SELECT 
            v.percentual_disconto,
            CASE WHEN v.origem = 'ARQUIVO' THEN 'Não se aplica' ELSE a.local_acesso END AS local_acesso,
            v.forma_pagamento,
            v.origem AS origem_usuario,
            v.valor_desconto,
            v.valor_pago,
            v.curso_uuid,
            v.usuario_uuid,
            v.data_venda
        FROM dataslight_dev.silver.tb_venda AS v
        JOIN dataslight_dev.silver.tb_acesso AS a ON v.acesso_uuid = a.acesso_uuid
    )
    SELECT 
        dt.sk_tempo,
        dcj.sk_codigos,
        dc.sk_curso,
        du.sk_usuario,
        ofv.valor_desconto,
        ofv.valor_pago
    FROM origem_fato_venda AS ofv
    JOIN dataslight_dev.gold.dim_codigos AS dcj ON  ofv.forma_pagamento = dcj.forma_pagamento
                                    AND ofv.origem_usuario = dcj.origem_usuario
                                    AND ofv.local_acesso = dcj.local_acesso
                                    AND ofv.percentual_disconto = dcj.percentual_disconto
    JOIN dataslight_dev.gold.dim_tempo AS dt ON dt.data = CAST(ofv.data_venda AS DATE)
    JOIN dataslight_dev.gold.dim_curso AS dc ON dc.curso_uuid = ofv.curso_uuid AND dc.__END_AT IS NULL
    JOIN dataslight_dev.gold.dim_usuario AS du ON du.usuario_uuid = ofv.usuario_uuid