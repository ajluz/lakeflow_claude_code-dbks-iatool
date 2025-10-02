# Databricks notebook source
# MAGIC %pip install dbldatagen

# COMMAND ----------

from pyspark.sql.types import *
from pyspark.sql.functions import expr, col, current_timestamp
import dbldatagen as dg
import time

# COMMAND ----------

import pyspark.sql.functions as F
from pyspark.sql.types import *

def generate_api_data(number_rows, run_as_batch=False):
    estados = ['RO','AC','AM','RR','PA','AP','TO','MA','PI','CE','RN','PB','PE','AL','SE','BA','MG','ES','RJ','SP','PR','SC','RS','MS','MT','GO','DF']
    profissao_usuario = ['Engenheiro de Dados','Arquiteto de Dados', 'Analista de Dados', 'Analista de BI', 'Cientista de Dados', 'Analista de Negocio', 'Desenvolvedor de ETL', 'Desenvolvedor de Sistemas']
    cursos = [
        'Construindo um Data Lakehouse com SQL e DLT', 
        'Mastering SQL no Databricks', 
        'Programa Data Heroes',
        'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    ]
    distribuicao_cursos = [30,21,45,4]

    valores_cursos = [247.00, 997.00, 2497.00, 0.00]
    distribuicao_valores_cursos = [30,21,45,4]

    provedores_email = ['@gmail.com','@hotmail.com','@outlook.com','@uol.com', '#yahoo.com', '#google.com']
    distribuicao_email = [39,29,19,9,2,2]

    sexo_usuario = ['M','F','X']
    distribuicao_sexo_usuario = [49,49,2]

    local_acesso = ['iphone', 'android','chrome','safari','firefox','unknown']
    distribuicao_local_acesso = [30,20,20,10,15,5]

    forma_pagamento = ['boleto','credito','pix','-----']
    distribuicao_forma_pagamento = [24, 69, 4, 3]

    disconto = [0.05,0.1,0.15]
    distribuicao_disconto = [50,35,15]
    
    parcelas = [1,2,3,10,12]
    distribuicao_parcelas = [20,15,5,30,30]

    idade = [18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50]
    number_unique_rows = 1000
    
    df_test = (
        dg.DataGenerator(spark, 
                        name="data_set", 
                        rows=number_unique_rows,
                        uniqueValues=number_unique_rows,
                        partitions=8, 
                        randomSeedMethod='hash_fieldname')
        .withIdOutput()

        .withColumn("id_venda", 
                    LongType(), 
                    minValue=0,
                    uniqueValues=number_unique_rows, 
                    omit=True)
        
        .withColumn("access_date", 
                    "timestamp",
                    begin="2024-06-01 00:00:00",
                    end="2025-12-31 23:59:59",
                    interval="247 seconds", 
                    baseColumn=["id_venda"])
        
        .withColumn("ip_address", 
                    StringType(),
                    expr="""case 
                        when rand() <= 0.01 then '999.999.999.999' 
                        else format_string('%d.%d.%d.%d', int(rand() * 255), int(rand() * 255), int(rand() * 255), int(rand() * 255)) 
                    end""",
                    baseColumn=["id_venda"])
        
        .withColumn("access_point", 
                    StringType(),
                    values=local_acesso,
                    weights=distribuicao_local_acesso,
                    baseColumn=["id_venda"])
        
        .withColumn("hash", 
                    StringType(),
                    omit=True, 
                    expr="md5(concat(cast(rand() as string),id_venda,access_date,ip_address,access_point))",
                    baseColumn=["id_venda","access_date","ip_address","access_point"])
        
        .withColumn("nome_usuario", 
                    StringType(),
                    omit=True, 
                    expr="concat('Usuario ', concat(left(hash,4),substr(hash,14,2),right(hash,4)))",
                    baseColumn=["hash"])
        
        .withColumn("provedor_email", 
                    "string", 
                    random=True, 
                    omit=True, 
                    weights=distribuicao_email,
                    values=provedores_email)
        
        .withColumn("email_usuario", 
                    StringType(),
                    omit=True, 
                    expr="concat('usuario_', concat(left(hash,4),substr(hash,14,2),right(hash,4)), provedor_email)",
                    baseColumn=["hash"])
        
        .withColumn("sexo", 
                    "string", 
                    random=True, 
                    omit=True, 
                    weights=distribuicao_sexo_usuario,
                    values=sexo_usuario)
        
        .withColumn("profissao", 
                    "string", 
                    random=True, 
                    omit=True, 
                    values=profissao_usuario)
        
        .withColumn("idade", 
                    "string", 
                    random=True, 
                    omit=True, 
                    values=idade)
        
        .withColumn("estado", 
                    StringType(),
                    omit=True, 
                    values=estados,
                    baseColumn="id_venda")
        
        .withColumn("product_name", 
                    StringType(),
                    omit=True, 
                    values=cursos,
                    weights=distribuicao_cursos,
                    baseColumn="id_venda")
        
        .withColumn("valor", 
                    DecimalType(9,2),
                    omit=True, 
                    values=valores_cursos,
                    weights=distribuicao_valores_cursos,
                    baseColumn=["id_venda"])
        
        .withColumn("valor_string", 
                    StringType(),
                    omit=True, 
                    expr="""case 
                        when product_name = 'Construindo um Data Lakehouse com SQL e DLT' 
                            then 'R$ 247,00' 
                        when product_name = 'Mastering SQL no Databricks' 
                            then 'R$ 997,00' 
                        when product_name = 'Programa Data Heroes' 
                            then 'R$ 2497,00' 
                        else 'R$ 0,00' end""",
                    baseColumn=["product_name"])
        
        .withColumn("disconto", 
                    DecimalType(9,2),
                    omit=True, 
                    values=disconto, 
                    nullable=True, 
                    percentNulls=0.7, 
                    weights=distribuicao_disconto,
                    baseColumn="id_venda")
        
        .withColumn("valor_disconto", 
                    DecimalType(9,2),
                    omit=True, 
                    expr="cast((valor * disconto) as numeric(9,2))",
                    baseColumn=["id_venda",'valor', 'disconto'])
        
        .withColumn("valor_pago", 
                    DecimalType(9,2),
                    omit=True, 
                    expr="cast((valor - coalesce(valor_disconto,0)) as numeric(9,2))",
                    baseColumn=["id_venda",'valor_disconto', 'valor'])
        
        .withColumn("forma_pagamento", 
                    StringType(),
                    omit=True, 
                    values=forma_pagamento, 
                    weights=distribuicao_forma_pagamento,
                    baseColumn="id_venda")
        
        .withColumn("quantidade_parcelas_base", 
                    LongType(),
                    omit=True, 
                    values=parcelas, 
                    weights=distribuicao_parcelas,
                    baseColumn="id_venda")
        
        .withColumn("quantidade_parcelas", 
                    StringType(),
                    omit=True, 
                    expr="""case when forma_pagamento in ('boleto','pix') 
                                then 1 
                            else quantidade_parcelas_base end""",
                    baseColumn=["id_venda",'quantidade_parcelas_base','forma_pagamento'])
        
        .withColumn("valor_parcelas", 
                    DecimalType(9,2),
                    omit=True, 
                    expr="cast((valor_pago/quantidade_parcelas) as numeric(9,2))",
                    baseColumn=["id_venda",'quantidade_parcelas','valor_pago'])
        
        .withColumn("info_usuario",
                    StructType([
                        StructField('nome',StringType()),
                        StructField('idade',StringType()),
                        StructField('sexo',StringType()),
                        StructField('email',StringType()),
                        StructField('profissao',StringType()),
                        StructField('estado',StringType())
                    ]),
                    omit=True, 
                    expr="""
                        named_struct(
                            'nome', nome_usuario, 
                            'idade', idade,
                            'sexo', sexo,
                            'email', email_usuario,
                            'profissao', profissao,
                            'estado', estado
                        )""",
                    nullable=True, 
                    percentNulls=0.7,
                    baseColumn=['nome_usuario','idade','sexo','email_usuario','profissao', 'estado'])
        
        .withColumn("info_produto",
                    StructType([
                        StructField('product_name',StringType()),
                        StructField('valor',StringType())
                    ]),
                    omit=True, 
                    expr="""
                        case when info_usuario is not null then 
                        named_struct(
                            'product_name', product_name, 
                            'valor', valor_string
                        )
                        else null end""",
                    nullable=True, 
                    percentNulls=0.7,
                    baseColumn=['info_usuario','product_name','valor_string'])
        
        .withColumn("info_pagamento",
                    StructType([
                        StructField('disconto',DecimalType(9,2)),
                        StructField('valor',DecimalType(9,2)),
                        StructField('forma_pagamento',StringType()),
                        StructField('quantidade_parcelas',LongType()),
                        StructField('valor_parcelas',DecimalType(9,2))
                    ]),
                    omit=True, 
                    expr="""
                        case when info_produto is not null then 
                        named_struct(
                            'disconto', disconto, 
                            'valor', valor_pago,
                            'forma_pagamento', forma_pagamento,
                            'quantidade_parcelas', quantidade_parcelas,
                            'valor_parcela', valor_parcelas
                        ) else null end""",
                    baseColumn=['info_produto','disconto','valor_pago','forma_pagamento','quantidade_parcelas','valor_parcelas'])
        
        .withColumn("payload",
                    StructType([
                        StructField('info_usuario',StructType([
                                                        StructField('nome',StringType()),
                                                        StructField('idade',StringType()),
                                                        StructField('sexo',StringType()),
                                                        StructField('email',StringType()),
                                                        StructField('profissao',StringType()),
                                                        StructField('estado',StringType())
                                                    ])),
                        StructField('info_produto',StructType([
                                                        StructField('product_name',StringType()),
                                                        StructField('valor',StringType())
                                                    ])),
                        StructField('info_pagamento',StructType([
                                                        StructField('disconto',DecimalType(9,2)),
                                                        StructField('valor',DecimalType(9,2)),
                                                        StructField('forma_pagamento',StringType()),
                                                        StructField('quantidade_parcelas',LongType()),
                                                        StructField('valor_parcelas',DecimalType(9,2))
                                                    ]))
                    ]),
                    expr="""
                        named_struct(
                            'info_usuario', info_usuario,
                            'info_produto', info_produto,
                            'info_pagamento', info_pagamento
                        )""",
                    baseColumn=['info_usuario','info_produto','info_pagamento'])
    )

    df = df_test.build(withStreaming=True, options={'rowsPerSecond': number_rows}).drop('id')
    
    if run_as_batch == True:
        generate_api_stream_data = (
            df.writeStream
                .format('json')
                .outputMode('append')
                .queryName('generate_api_stream_data')
                ### Adicionado para funcionar no databricks Free
                ### Se você estiver estudando em um ambiente fora do Free 
                ### a linha de trigger pode ser removida e o processo vai rodar
                ### continuamente.
                .trigger(availableNow=True)
                .option('checkpointLocation','/Volumes/workspace/bronze/landing/_checkpoint_stream')
                .start("/Volumes/workspace/bronze/landing/stream")
        )
    else:
        generate_api_stream_data = (
            df.writeStream
                .format('json')
                .outputMode('append')
                .queryName('generate_api_stream_data')
                .option('checkpointLocation','/Volumes/workspace/bronze/landing/_checkpoint_stream')
                .start("/Volumes/workspace/bronze/landing/stream")
        )   
    
    return generate_api_stream_data

# COMMAND ----------

def generate_files_data(number_rows):
    estados = ['RO','AC','AM','RR','PA','AP','TO','MA','PI','CE','RN','PB','PE','AL','SE','BA','MG','ES','RJ','SP','PR','SC','RS','MS','MT','GO','DF']
    sexo_usuario = ['M','F']
    profissao_usuario = ['Engenheiro de Dados','Arquiteto de Dados', 'Analista de Dados', 'Analista de BI', 'Cientista de Dados', 'Analista de Negocio', 'Desenvolvedor de ETL', 'Desenvolvedor de Sistemas']
    cursos = [
        'Construindo um Data Lakehouse com SQL e DLT', 
        'Mastering SQL no Databricks', 
        'Programa Data Heroes'
    ]
    empresas = ['Empresa A', 'Empresa B', 'Empresa C', 'Empresa D','Empresa E','Empresa F','Empresa G','Empresa H','Empresa I','Empresa J','Empresa L','Empresa M','Empresa N']
    distribuicao_empresas = [30,5,3,2,10,1,5,15,1,8,5,12,7]
    disconto = ['5%','10%','15%']
    idade = [18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50]
    number_unique_rows = number_rows

    df_test = (
        dg.DataGenerator(spark, 
                        name="data_set", 
                        rows=number_unique_rows,
                        uniqueValues=number_unique_rows,
                        partitions=8, 
                        randomSeedMethod='hash_fieldname')
        .withIdOutput()

        .withColumn("id_venda", 
                    LongType(), 
                    minValue=0,
                    uniqueValues=number_unique_rows, 
                    omit=True)
        
        .withColumn("data_venda", 
                    "date",
                    begin="2024-06-01",
                    end="2025-12-31",
                    interval="10 days", 
                    random=True,
                    baseColumn=["id_venda"])
        
        .withColumn("nome_empresa", 
                    StringType(),
                    values=empresas,
                    weights=distribuicao_empresas,
                    baseColumn=["id_venda"])
        
        .withColumn("sexo", 
                    "string", 
                    random=True, 
                    values=sexo_usuario)
        
        .withColumn("hash", 
                    StringType(),
                    omit=True, 
                    expr="md5(concat(cast(rand() as string),id_venda,data_venda,nome_empresa,sexo))",
                    baseColumn=["id_venda","data_venda","nome_empresa","sexo"])
        
        .withColumn("nome_funcionario", 
                    StringType(), 
                    expr="concat('Funcionario ',concat(left(hash,4),substr(hash,14,2),right(hash,4)))",
                    baseColumn=["hash"])
        
        .withColumn("provedor_email", 
                    "string", 
                    omit=True, 
                    expr="concat('@',replace(lower(nome_empresa),' ',''),'.com.br')",
                    baseColumn=["nome_empresa"])
        
        .withColumn("email_funcionario", 
                    StringType(),
                    expr="concat(lower(replace(nome_funcionario,' ','_')), provedor_email)",
                    baseColumn=["nome_funcionario","provedor_email"])
        
        .withColumn("profissao", 
                    "string", 
                    random=True, 
                    values=profissao_usuario)
        
        .withColumn("idade", 
                    "string", 
                    random=True, 
                    values=idade)
        
        .withColumn("estado", 
                    StringType(),
                    values=estados,
                    baseColumn="id_venda")
        
        .withColumn("curso", 
                    StringType(),
                    values=cursos,
                    baseColumn="id_venda")
        
        .withColumn("valor", 
                    StringType(),
                    expr="case when curso = 'Construindo um Data Lakehouse com SQL e DLT' then 'R$ 247,00' when curso = 'Mastering SQL no Databricks' then 'R$ 997,00' when curso = 'Programa Data Heroes' then 'R$ 2497,00' end",
                    baseColumn=["id_venda"])
        
        .withColumn("disconto", 
                    StringType(),
                    expr="case when nome_empresa in ('Empresa A', 'Empresa G','Empresa H') then '5%' when nome_empresa in ('Empresa F','Empresa D','Empresa E') then '10%' else '15%' end",
                    baseColumn=["id_venda","nome_empresa"])
    )

    df = df_test.build().drop('id')

    df.coalesce(1).write.format('csv').mode('append').option('header',True).option('sep',',').save('/Volumes/workspace/bronze/landing/files')

    exclusion_list = ['_committed','_started','_SUCCESS']
    for file_to_be_excluded in exclusion_list:
        for file in dbutils.fs.ls('/Volumes/workspace/bronze/landing/files'):
            if file_to_be_excluded in file.name:
                dbutils.fs.rm(f'/Volumes/workspace/bronze/landing/files/{file.name}')

    spark.read.text(f'/Volumes/workspace/bronze/landing/files/{file.name}').limit(2)

    return print(f"O arquivo .csv com {number_rows} registros foi gerado no diretorio '/Volumes/workspace/bronze/landing/files'.")

# COMMAND ----------

def generate_database_data(type_of_data='initial setup'):
    if type_of_data == 'initial setup':
        curso_df = spark.sql("""
                SELECT 
                md5('Construindo um Data Lakehouse com SQL e DLT') AS curso_uuid,
                    'Construindo um Data Lakehouse com SQL e DLT' AS nome_curso,
                    'beginner' AS nivel_curso,
                    247.00 AS valor_curso,
                    'insert' AS change_type,
                    current_timestamp() AS timestamp_change

                UNION 

                SELECT 
                    md5('Mastering SQL no Databricks') AS curso_uuid,
                    'Mastering SQL no Databricks' AS nome_curso,
                    'intermediate' AS nivel_curso,
                    997.00 AS valor_curso,
                    'insert' AS change_type,
                    current_timestamp() AS timestamp_change

                UNION 

                SELECT 
                    md5('Programa Data Heroes') AS curso_uuid,
                    'Programa Data Heroes' AS nome_curso,
                    'advanced' AS nivel_curso,
                    2497.00 AS valor_curso,
                    'insert' AS change_type,
                    current_timestamp() AS timestamp_change
        """)
        curso_df.coalesce(1).write.format('csv').option('header',True).option('sep',',').mode('overwrite').save('/Volumes/workspace/bronze/landing/database')
        print(f'O arquivo de INSERT com origem DATABASE foi criado com sucesso.')

    elif type_of_data == 'update row':
        curso_df = spark.sql("""
        SELECT 
            md5('Construindo um Data Lakehouse com SQL e DLT') AS curso_uuid,
            'Construindo um Data Lakehouse com SQL e DLT' AS nome_curso,
            'beginner' AS nivel_curso,
            147.00 AS valor_curso,
             'update' AS change_type,
            current_timestamp() AS timestamp_change
        """)
        curso_df.coalesce(1).write.format('csv').option('header',True).option('sep',',').mode('append').save('/Volumes/workspace/bronze/landing/database')
        print(f'O arquivo de UPDATE com origem DATABASE foi criado com sucesso.')

    elif type_of_data == 'delete row':
        curso_df = spark.sql("""
        SELECT 
            md5('Construindo um Data Lakehouse com SQL e DLT') AS curso_uuid,
            'Construindo um Data Lakehouse com SQL e DLT' AS nome_curso,
            'beginner' AS nivel_curso,
            147.00 AS valor_curso,
             'delete' AS change_type,
            current_timestamp() AS timestamp_change
        """)
        curso_df.coalesce(1).write.format('csv').option('header',True).option('sep',',').mode('append').save('/Volumes/workspace/bronze/landing/database')
        print(f'O arquivo de DELETE com origem DATABASE foi criado com sucesso.')

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE TABLE IF NOT EXISTS workspace.gold.dim_tempo (
# MAGIC   sk_tempo BIGINT GENERATED BY DEFAULT AS IDENTITY,
# MAGIC   data DATE,
# MAGIC   ano INT,
# MAGIC   mes STRING,
# MAGIC   mes_ano INT,
# MAGIC   dia_semana_int INT,
# MAGIC   dia_semana STRING,
# MAGIC   fl_dia_semana BOOLEAN,
# MAGIC   dia_mes INT,
# MAGIC   fl_ultimo_dia_mes BOOLEAN,
# MAGIC   dia_ano INT,
# MAGIC   semana_ano INT,
# MAGIC   bimestre INT,
# MAGIC   trimestre INT,
# MAGIC   semestre INT,
# MAGIC   data_carga TIMESTAMP
# MAGIC )
# MAGIC TBLPROPERTIES ("quality" = "gold");
# MAGIC
# MAGIC INSERT INTO workspace.gold.dim_tempo (
# MAGIC   data,
# MAGIC   ano,
# MAGIC   mes,
# MAGIC   mes_ano,
# MAGIC   dia_semana_int,
# MAGIC   dia_semana,
# MAGIC   fl_dia_semana,
# MAGIC   dia_mes,
# MAGIC   fl_ultimo_dia_mes,
# MAGIC   dia_ano,
# MAGIC   semana_ano,
# MAGIC   bimestre,
# MAGIC   trimestre,
# MAGIC   semestre,
# MAGIC   data_carga
# MAGIC )
# MAGIC
# MAGIC   with datas as (
# MAGIC     select
# MAGIC       explode(
# MAGIC         sequence(
# MAGIC           to_date('2024-06-01'),
# MAGIC           to_date('2026-12-31'),
# MAGIC           interval 1 day
# MAGIC         )
# MAGIC       ) as data
# MAGIC   )
# MAGIC   select
# MAGIC     data,
# MAGIC     year(data) AS ano,
# MAGIC     to_csv(
# MAGIC       named_struct('date', data),
# MAGIC       map('dateFormat', 'MMMM', 'locale', 'PT')
# MAGIC     ) AS mes,
# MAGIC     month(data) as mes_ano,
# MAGIC     dayofweek(data) AS dia_semana_int,
# MAGIC     to_csv(
# MAGIC       named_struct('date', data),
# MAGIC       map('dateFormat', 'EEEE', 'locale', 'PT')
# MAGIC     ) AS dia_semana,
# MAGIC     case
# MAGIC       when weekday(data) < 5 then True
# MAGIC       else False
# MAGIC     end as fl_dia_semana,
# MAGIC     dayofmonth(data) as dia_mes,
# MAGIC     case
# MAGIC       when data = last_day(data) then True
# MAGIC       else False
# MAGIC     end as fl_ultimo_dia_mes,
# MAGIC     dayofyear(data) as dia_ano,
# MAGIC     weekofyear(data) as semana_ano,
# MAGIC     case
# MAGIC       when month(data) in (1, 2) then 1
# MAGIC       when month(data) in (3, 4) then 2
# MAGIC       when month(data) in (5, 6) then 3
# MAGIC       when month(data) in (7, 8) then 4
# MAGIC       when month(data) in (9, 10) then 5
# MAGIC       when month(data) in (11, 12) then 6
# MAGIC     end as bimestre,
# MAGIC     case
# MAGIC       when month(data) in (1, 2, 3) then 1
# MAGIC       when month(data) in (4, 5, 6) then 2
# MAGIC       when month(data) in (7, 8, 9) then 3
# MAGIC       when month(data) in (10, 11, 12) then 4
# MAGIC     end as trimestre,
# MAGIC     case
# MAGIC       when month(data) in (1, 2, 3, 4, 5, 6) then 1
# MAGIC       when month(data) in (7, 8, 9, 10, 11, 12) then 2
# MAGIC     end as semestre,
# MAGIC     current_timestamp() AS data_carga
# MAGIC   from datas;
# MAGIC
# MAGIC -- SELECT * FROM workspace.gold.dim_tempo;
