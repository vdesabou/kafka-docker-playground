from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("").getOrCreate()

print("creating database")
spark.sql('CREATE DATABASE IF NOT EXISTS orders')

print("creating table")
spark.sql('''
    CREATE TABLE IF NOT EXISTS orders.payments (  
        id                                                   STRING,
        type                                                 STRING,
        created_at                                           TIMESTAMP,
        document                                             STRING,
        payer                                                STRING,
        amount                                               INT
    )
    USING iceberg
    PARTITIONED BY (document)
''')
