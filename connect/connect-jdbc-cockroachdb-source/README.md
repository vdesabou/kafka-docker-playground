# JDBC CockroachDB source connector

## Objective

Quickly test [JDBC CockroachDB](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.


## How to run

Simply run:

```
$ playground run -f cockroachdb<tab>
```

N.B: CockroachDB DB Console is reachable at [http://127.0.0.1:8080](http://127.0.0.1:8080])

## Details of what the script is doing

Create table drivers

```bash
$ docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
CREATE SEQUENCE rownum_seq;
CREATE TABLE IF NOT EXISTS drivers (
    rownum INT DEFAULT nextval('rownum_seq'),
    id UUID NOT NULL,
    city STRING NOT NULL,
    name STRING,
    dl STRING,
    address STRING,
    INDEX name_idx (name),
    CONSTRAINT "primary" PRIMARY KEY (city ASC, id ASC)
);
EOF
```

Adding 2 elements to the table

```bash
$ docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address) VALUES
    ('8a3d70a3-d70a-4000-8000-00000000001b', 'seattle', 'Eric', 'GHI-9123', '400 Broad St'),
    ('9eb851eb-851e-4800-8000-00000000001f', 'new york', 'Harry Potter', 'JKL-456', '214 W 43rd St');
EOF
```

Show content of CUSTOMERS table:

```bash
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
SELECT * FROM drivers;
EOF
```

Creating JDBC CockroachDB source connector

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://cockroachdb:26257/defaultdb?user=root&sslmode=disable",
               "table.whitelist": "drivers",
               "mode": "incrementing",
               "incrementing.column.name": "rownum",
               "topic.prefix": "cockroachdb-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/cockroachdb-source/config | jq .
```

Verifying topic `cockroachdb-drivers`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic cockroachdb-drivers --from-beginning --max-messages 2
```

Results:

```json
{"rownum":{"long":1},"id":{"string":"8a3d70a3-d70a-4000-8000-00000000001b"},"city":{"string":"seattle"},"name":{"string":"Eric"},"dl":{"string":"GHI-9123"},"address":{"string":"400 Broad St"}}
{"rownum":{"long":2},"id":{"string":"9eb851eb-851e-4800-8000-00000000001f"},"city":{"string":"new york"},"name":{"string":"Harry Potter"},"dl":{"string":"JKL-456"},"address":{"string":"214 W 43rd St"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
