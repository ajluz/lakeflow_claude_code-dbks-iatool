-- Camada gold: dimensão de cursos (dim_curso). SCD tipo 2.
-- Grão: uma versão de um curso, mais os membros padrão, vindos de vw_gold_dim_curso_membros.
-- __START_AT e __END_AT guardam o timestamp_change do evento que abriu e do que fechou a
-- versão. A versão atual é a linha com __END_AT IS NULL.
-- Mesma chave, ordem e condição de exclusão de silver.tb_curso (Princípio I): a versão
-- atual de cada curso é sempre igual à linha de silver.
-- Uma atualização fecha a versão aberta e abre outra; uma exclusão fecha a versão aberta e
-- não remove nenhuma linha.
-- Sem TRACK HISTORY: sk_curso e data_carga mudam a cada evento, e rastrear só os atributos
-- sobrescreveria a chave da versão atual.
-- Os fatos resolvem sk_curso pela versão do curso_uuid em vigor na data do fato
-- ([__START_AT, __END_AT)); sem correspondência, usam -1.

CREATE OR REFRESH STREAMING TABLE presentation.gold.dim_curso
COMMENT 'Dimensão de cursos com histórico (SCD tipo 2): uma linha por versão de cada curso, com chave substituta por versão, validade em __START_AT e __END_AT e os membros Desconhecido (-1) e Não se aplica (-2).'
TBLPROPERTIES ("quality" = "gold");

-- Versões dos cursos, a partir do feed de mudanças.
CREATE FLOW gold_dim_curso_flow AS AUTO CDC INTO presentation.gold.dim_curso
FROM STREAM(vw_gold_dim_curso_dados_database)
KEYS (curso_uuid)
APPLY AS DELETE WHEN change_type = 'delete'
SEQUENCE BY timestamp_change
COLUMNS * EXCEPT (change_type, timestamp_change)
STORED AS SCD TYPE 2;

-- Membros padrão, uma única vez (ONCE): o fluxo lê a view uma vez e fica ocioso, então os
-- membros nunca são reenviados, nem quando chegam mudanças do catálogo. Mesmas cláusulas do
-- fluxo das versões.
CREATE FLOW gold_dim_curso_membros_flow AS AUTO CDC ONCE INTO presentation.gold.dim_curso
FROM STREAM(vw_gold_dim_curso_membros)
KEYS (curso_uuid)
APPLY AS DELETE WHEN change_type = 'delete'
SEQUENCE BY timestamp_change
COLUMNS * EXCEPT (change_type, timestamp_change)
STORED AS SCD TYPE 2;
