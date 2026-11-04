-- Camada gold: view do fluxo AUTO CDC de silver.tb_usuario para dim_usuario.
-- Um fluxo AUTO CDC não calcula colunas, então os cálculos ficam aqui:
--   sk_usuario: xxhash64 de usuario_uuid com o bit de sinal zerado, um BIGINT não negativo
--     que nunca muda para o mesmo usuário. Colunas de identidade não são suportadas em
--     alvos de AUTO CDC. Chaves negativas ficam reservadas aos membros padrão;
--   data_carga: o horário em que gold gravou a linha;
--   data_carga_silver: o horário de silver, usado só para ordenar as mudanças do fluxo.
-- Membros padrão: -1 'Desconhecido' e -2 'Não se aplica', com chaves fixas.
-- O Spark não aceita UNION entre um fluxo e linhas literais. Por isso cada linha de silver
-- gera três linhas: o usuário e os dois membros. O fluxo AUTO CDC guarda uma linha por chave,
-- então os membros repetidos viram uma linha de cada na dimensão.

CREATE TEMPORARY VIEW vw_gold_dim_usuario_tb_usuario
COMMENT 'Usuários de silver.tb_usuario com a chave substituta calculada e os dois membros padrão, no formato do fluxo AUTO CDC de dim_usuario.'
AS
SELECT linha.*
FROM STREAM(workspace.silver.tb_usuario) AS u
LATERAL VIEW explode(array(
  named_struct(
    'sk_usuario',        xxhash64(u.usuario_uuid) & 9223372036854775807,
    'usuario_uuid',      u.usuario_uuid,
    'nome_usuario',      u.nome_usuario,
    'email_usuario',     u.email_usuario,
    'idade_usuario',     u.idade_usuario,
    'sexo_usuario',      u.sexo_usuario,
    'estado_usuario',    u.estado_usuario,
    'profissao_usuario', u.profissao_usuario,
    'empresa_usuario',   u.empresa_usuario,
    'origem',            u.origem,
    'data_carga',        current_timestamp(),
    'data_carga_silver', u.data_carga
  ),
  named_struct(
    'sk_usuario',        CAST(-1 AS BIGINT),
    'usuario_uuid',      '-1',
    'nome_usuario',      'Desconhecido',
    'email_usuario',     'Desconhecido',
    'idade_usuario',     CAST(NULL AS INT),
    'sexo_usuario',      'Desconhecido',
    'estado_usuario',    'Desconhecido',
    'profissao_usuario', 'Desconhecido',
    'empresa_usuario',   'Desconhecido',
    'origem',            'Desconhecido',
    'data_carga',        current_timestamp(),
    'data_carga_silver', TIMESTAMP'1900-01-01'
  ),
  named_struct(
    'sk_usuario',        CAST(-2 AS BIGINT),
    'usuario_uuid',      '-2',
    'nome_usuario',      'Não se aplica',
    'email_usuario',     'Não se aplica',
    'idade_usuario',     CAST(NULL AS INT),
    'sexo_usuario',      'Não se aplica',
    'estado_usuario',    'Não se aplica',
    'profissao_usuario', 'Não se aplica',
    'empresa_usuario',   'Não se aplica',
    'origem',            'Não se aplica',
    'data_carga',        current_timestamp(),
    'data_carga_silver', TIMESTAMP'1900-01-01'
  )
)) AS linha;
