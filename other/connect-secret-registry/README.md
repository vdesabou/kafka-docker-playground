# Connect Secret Registry

## Objective

Quickly test [Connect Secret Registry](https://docs.confluent.io/platform/current/connect/rbac/connect-rbac-secret-registry.html#kconnect-secret-registry).

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Details of what the script is doing

Rolebindings explained [here](https://docs.confluent.io/platform/current/connect/rbac/connect-rbac-connect-cluster.html#configuring-rbac-for-a-kconnect-cluster) are already specified in playground's RBAC environment [here](https://github.com/vdesabou/kafka-docker-playground/blob/83d37281dec01193386aa39a551725bceb77cfa0/environment/rbac-sasl-plain/scripts/helper/create-role-bindings.sh#L100-L116):

```bash
# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"     <------ here
    "Group:secret-registry"        <------ here
)
for resource in ${ConnectResources[@]}
do
    confluent iam rolebinding create \
        --principal $CONNECT_ADMIN \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done
```

Sending messages to topic rbac_topic:

```bash
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_without_interceptors.config
```

Registering secret `username` with superUser:

```bash
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/username/versions | jq .
```

Registering secret `password` with superUser:

```bash
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/password/versions | jq .
```

Creating FileStream Sink connector:

```bash
playground connector create-or-update --connector my-rbac-connector << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "rbac_topic",
               "file": "/tmp/output.json",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter.basic.auth.user.info": "connectorSA:connectorSA",
               "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"${secret:my-rbac-connector:username}\" password=\"${secret:my-rbac-connector:password}\" metadataServerUrls=\"http://broker:8091\";"
          }
EOF
```

Verify we have received the data in file:

```bash
docker exec connect cat /tmp/output.json
```

Results:

```
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 1}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 2}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 3}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 4}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 5}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 6}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 7}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 8}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 9}
Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 10}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
