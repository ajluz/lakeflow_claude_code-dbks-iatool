CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.obt_acesso
TBLPROPERTIES ("quality" = "gold")
AS
    SELECT 
        a.local_acesso,
        a.endereco_ip_acesso,
        t.data,
        t.ano,
        t.mes,
        t.mes_ano,
        t.dia_mes,
        t.dia_semana,
        t.dia_semana_int,
        t.fl_dia_semana,
        t.dia_ano,
        t.fl_ultimo_dia_mes,
        t.semana_ano,
        t.semestre,
        t.trimestre,
        t.bimestre,
        1 AS qtde_acesso,
        CASE WHEN a.usuario_uuid IS NOT NULL THEN 1 ELSE 0 END AS qtde_usuario,
        CASE WHEN v.valor_parcelas IS NOT NULL THEN 1 ELSE 0 END AS qtde_vendidos
    FROM workspace.silver.tb_acesso AS a
    JOIN workspace.gold.dim_tempo AS t ON CAST(a.timestamp_acesso AS DATE) = t.data
    LEFT JOIN workspace.silver.tb_venda v ON a.acesso_uuid = v.acesso_uuid;