CREATE OR REFRESH STREAMING LIVE TABLE workspace.silver.tb_usuario(
    CONSTRAINT check_sexo_usuario EXPECT (
        sexo_usuario IN ('M', 'F')
    ) ON VIOLATION DROP ROW,
    CONSTRAINT check_email_usuario EXPECT (
        email_usuario LIKE '%@%'
    ) 
)
TBLPROPERTIES ("quality" = "silver")
AS 
  SELECT 
      md5(concat(
          CAST(access_date AS TIMESTAMP),
          payload.info_usuario.nome
      )) AS usuario_uuid,
      payload.info_usuario.nome AS nome_usuario,
      payload.info_usuario.email AS email_usuario,
      CAST(payload.info_usuario.idade AS INT) AS idade_usuario,
      payload.info_usuario.sexo AS sexo_usuario,
      payload.info_usuario.estado AS estado_usuario,
      payload.info_usuario.profissao AS profissao_usuario,
      CAST(NULL AS STRING) AS empresa_usuario,
      'API' AS origem,
      getdate() AS data_carga
  FROM STREAM(workspace.silver.temp_tb_validacao_api)
  WHERE payload.info_usuario IS NOT NULL
    AND fl_registro_invalido=FALSE

  UNION ALL

  SELECT 
      md5(concat(
          nome_empresa,
          nome_funcionario
      )) AS usuario_uuid,
      nome_funcionario AS nome_usuario,
      email_funcionario AS email_usuario,
      CAST(idade AS INT) AS idade_usuario,
      sexo AS sexo_usuario,
      estado AS estado_usuario,
      profissao AS profissao_usuario,
      nome_empresa AS empresa_usuario,
      'ARQUIVO' AS origem,
      getdate() AS data_carga
  FROM STREAM(vw_bronze_dados_files);