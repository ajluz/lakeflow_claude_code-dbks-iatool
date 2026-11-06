# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC ### Setup

# COMMAND ----------

# MAGIC %run "./functions"

# COMMAND ----------

generate_files_data(number_rows=100000)
generate_database_data(type_of_data='initial setup')

# no Databricks Free não conseguimos realizar uma stream query continua. 
# A simulação de Stream vai rodar como batch para fins de estudo.
query = generate_api_data(number_rows=3876831, run_as_batch=True)

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dados na Zona Bronze

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM presentation.bronze.dados_database

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM presentation.bronze.dados_files

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM presentation.bronze.dados_api
# MAGIC WHERE 1=1
# MAGIC -- -- QUARENTENA - Tabela para analises futuras
# MAGIC AND payload.info_produto.product_name = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
# MAGIC   OR payload.info_pagamento.valor = '0.00'
# MAGIC   OR payload.info_pagamento.forma_pagamento = '-----'
# MAGIC
# MAGIC -- -- Constraint de Check e Drop para Clientes
# MAGIC -- AND payload.info_usuario.email like '%#%'
# MAGIC --   OR payload.info_usuario.sexo like '%X%'
# MAGIC
# MAGIC -- -- Constraint de Check e Drop para Clientes
# MAGIC -- AND ip_address = '999.999.999.999'
# MAGIC --   OR access_point = 'unknown'

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dados na Zona Silver

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.silver.tb_quarentena

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.silver.tb_acesso

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.silver.tb_usuario

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.silver.tb_venda 
# MAGIC WHERE acesso_uuid is not null
# MAGIC LIMIT 10

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.silver.tb_curso

# COMMAND ----------

spark.sql('SELECT * FROM presentation.bronze.dados_database').display()
spark.sql('SELECT * FROM presentation.silver.tb_curso').display()

# COMMAND ----------

generate_database_data(type_of_data='update row')

# COMMAND ----------

spark.sql('SELECT * FROM presentation.bronze.dados_database').display()
spark.sql('SELECT * FROM presentation.silver.tb_curso').display()

# COMMAND ----------

# MAGIC %md
# MAGIC ### Dados na Zona Gold

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.gold.dim_tempo LIMIT 10

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.gold.dim_codigos

# COMMAND ----------

# MAGIC %sql SELECT * FROM presentation.gold.dim_usuario ORDER BY sk_usuario ASC

# COMMAND ----------

spark.sql('SELECT * FROM presentation.bronze.dados_database').display()
spark.sql('SELECT * FROM presentation.silver.tb_curso').display()
spark.sql('SELECT * FROM presentation.gold.dim_curso').display()

# COMMAND ----------

generate_database_data(type_of_data='delete row')

# COMMAND ----------

spark.sql('SELECT * FROM presentation.bronze.dados_database').display()
spark.sql('SELECT * FROM presentation.silver.tb_curso').display()
spark.sql('SELECT * FROM presentation.gold.dim_curso').display()

# COMMAND ----------

# MAGIC %sql SELECT * from presentation.gold.fato_venda

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC     COUNT(*) AS quantidade_cursos_vendidos,
# MAGIC     SUM(f.valor_pago) - SUM(f.valor_desconto) AS valor_faturamento_bruto
# MAGIC FROM presentation.gold.fato_venda as f
# MAGIC JOIN presentation.gold.dim_codigos AS cd ON f.sk_codigos = cd.sk_codigos
# MAGIC JOIN presentation.gold.dim_curso AS cs ON f.sk_curso = cs.sk_curso 
# MAGIC JOIN presentation.gold.dim_tempo AS t ON f.sk_tempo = t.sk_tempo
# MAGIC JOIN presentation.gold.dim_usuario AS u ON f.sk_usuario = u.sk_usuario
# MAGIC WHERE t.ano = 2024
# MAGIC   AND t.mes = 'junho'
# MAGIC   AND cd.local_acesso = 'Mobile'
# MAGIC   AND cd.percentual_desconto = '5%'

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   SUM(qtde_acesso) AS quantidade_acessos,
# MAGIC   SUM(qtde_usuario) AS quantidade_usuario,
# MAGIC   SUM(qtde_vendidos) AS quantidade_vendas,
# MAGIC   CAST((SUM(qtde_vendidos)/SUM(qtde_acesso))*100 AS INT) AS percentual_vendas
# MAGIC FROM presentation.gold.obt_acesso
# MAGIC WHERE local_acesso = 'Computador'
# MAGIC   AND mes = 'junho'
# MAGIC   AND ano = 2024
# MAGIC   AND fl_dia_semana is false