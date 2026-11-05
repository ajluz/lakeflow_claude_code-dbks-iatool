-- Camada gold: view do fluxo AUTO CDC de silver.tb_usuario para dim_usuario.
-- sk_usuario: xxhash64 de usuario_uuid com o bit de sinal zerado, um BIGINT não negativo
-- que nunca muda para o mesmo usuário. Chaves negativas ficam para os membros padrão.
-- data_carga: horário em que gold gravou a linha.
-- data_carga_silver: horário de silver, usado só para ordenar as mudanças.

CREATE TEMPORARY VIEW vw_gold_dim_usuario_tb_usuario
COMMENT 'Usuários de silver.tb_usuario com a chave substituta calculada, no formato do fluxo AUTO CDC de dim_usuario.'
AS
SELECT
  xxhash64(usuario_uuid) & 9223372036854775807 AS sk_usuario,
  usuario_uuid,
  nome_usuario,
  email_usuario,
  idade_usuario,
  sexo_usuario,
  estado_usuario,
  profissao_usuario,
  empresa_usuario,
  origem,
  current_timestamp() AS data_carga,
  data_carga          AS data_carga_silver
FROM STREAM(workspace.silver.tb_usuario);
