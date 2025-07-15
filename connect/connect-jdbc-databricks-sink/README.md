# JDBC Databricks Sink connector



## Objective

Quickly test [JDBC Databricks Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector) connector.


## Register a trial account

Go to [Databricks](https://www.databricks.com/try-databricks) and register for a trial.

Once the trial instance is ready, login the portal 
Navigate to the SQL Warehouses -> Connection details to collect the Server hostname, HTTP Path.
Click on your Account on the top right corner, select Settings. Select Developer and generate a new Personal Access token.

Export the below Environment vairables

DATABRICKS_HOST

DATABRICKS_TOKEN

DATABRICKS_HTTP_PATH

## How to run

Simply run:

```
$ just use <playground run> command and search for databricks-sink.sh in this folder
```

## Details of what the script is doing

Create table in Databricks:

```bash
docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
CREATE OR REPLACE TABLE orders ( id INT, product STRING, quantity INT, price FLOAT )TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');
exit
EOF
```

Creating Databricks JDBC Sink connector:

```bash
playground connector create-or-update --connector databricks-sink << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "auto.create": "false",
  "auto.evolve": "false",
  "connection.url": "jdbc:databricks://$DATABRICKS_HOST:443/default;transportMode=http;ssl=1;AuthMech=3;httpPath=$DATABRICKS_HTTP_PATH;IgnoreTransactions=1;",
  "connection.user": "token",
  "connection.password" : "$DATABRICKS_TOKEN",
  "topics": "orders"
}
EOF
```

Send messages to the topic
```bash
playground topic produce -t orders --nb-messages 3 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
       "type":  "string"
    },
    {
      "name": "quantity",
      "type":  "int"
    },
    {
      "name": "price",
       "type": "float"
    }
  ]
}
EOF
```

Verify that the data is available in the orders table 
```bash
docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
select count(*) from orders;
exit
EOF
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
