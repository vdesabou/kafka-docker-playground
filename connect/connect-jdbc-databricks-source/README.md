# JDBC Databricks Source connector



## Objective

Quickly test [JDBC Databricks Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector) connector.

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
$ just use <playground run> command and search for databricks-source.sh in this folder
```

## Details of what the script is doing

Create table in Databricks:

```bash
docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
create or replace table CUSTOMERS ( id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, first_name VARCHAR(50), last_name VARCHAR(50), email VARCHAR(50), gender VARCHAR(50), club_status VARCHAR(20), comments VARCHAR(90), create_ts timestamp DEFAULT CURRENT_TIMESTAMP , update_ts timestamp DEFAULT CURRENT_TIMESTAMP ) TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Even', 'Tinham', 'etinham8@facebook.com', 'Male', 'silver', 'Virtual full-range info-mediaries');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Brena', 'Tollerton', 'btollerton9@furl.net', 'Female', 'silver', 'Diverse tangible methodology');

select * from customers order by id;
exit
EOF

```

Creating Databricks JDBC Source connector:

```bash
playground connector create-or-update --connector jdbc-databricks-source  << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "mode": "incrementing",
               "table.whitelist": "customers",
               "incrementing.column.name": "id",
               "connection.url": "jdbc:databricks://$DATABRICKS_HOST:443/default;transportMode=http;ssl=1;AuthMech=3;httpPath=$DATABRICKS_HTTP_PATH;IgnoreTransactions=1;",
               "connection.user": "token",
               "connection.password" : "$DATABRICKS_TOKEN",
               "topic.prefix": "databricks-"
          }
EOF
```

sleep 5

Verifying topic databricks-CUSTOMERS:

```bash
playground topic consume --topic databricks-customers --min-expected-messages 1 --timeout 60
```

Results:

```json
{"id": {"long": 1},"first_name": {"string": "Rica"},"last_name": {"string": "Blaisdell"},"email": {"string": "rblaisdell0@rambler.ru"},"gender": {"string": "Female"},"club_status": {"string": "bronze"},"comments": {"string": "Universal optimal hierarchy"},"create_ts": {"long": 1748960479035},"update_ts": {"long": 1748960479036}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
