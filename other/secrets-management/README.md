# Secrets Management with Connect

## Objective

Quickly test [Secrets Management](https://docs.confluent.io/platform/current/security/secrets.html#secrets-management).

## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

```bash
docker run -i --rm -v ${DIR}/secrets:/secrets cnfldemos/tools:0.3 bash -c '
echo "Generate master key"
confluent-v1 secret master-key generate --local-secrets-file /secrets/secret.txt --passphrase @/secrets/passphrase.txt > /tmp/result.log 2>&1
cat /tmp/result.log
export CONFLUENT_SECURITY_MASTER_KEY=$(grep "Master Key" /tmp/result.log | cut -d"|" -f 3 | sed "s/ //g" | tail -1 | tr -d "\n")
echo "$CONFLUENT_SECURITY_MASTER_KEY" > /secrets/CONFLUENT_SECURITY_MASTER_KEY
echo "Encrypting my-secret-property in file my-config-file.properties"
confluent-v1 secret file encrypt --local-secrets-file /secrets/secret.txt --remote-secrets-file /etc/kafka/secrets/secret.txt --config my-secret-property --config-file /secrets/my-config-file.properties
'
```

Sending messages to topic my-secret-value:

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic my-secret-value << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
```

Creating FileStream Sink connector with topics set with secrets variable:

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "${securepass:/etc/kafka/secrets/secret.txt:my-config-file.properties/my-secret-property}",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-sink/config | jq .
```

Verify we have received the data in file:

```bash
docker exec connect cat /tmp/output.json
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
