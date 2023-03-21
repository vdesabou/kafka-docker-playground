#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls.yml"

log "Creating http-source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "http.request.url": "https://http-service-mtls-auth:8443/api/messages",
               "kafka.topic": "http-topic-messages",

               "http.client.keystore": "/tmp/keystore.http-service-mtls-auth.p12",
               "http.client.keystore.password": "confluent"
          }' \
     http://localhost:8083/connectors/http-cdc-sourc2e/config | jq .


sleep 3

log "Send a message to HTTP server"
curl --cert ../../connect/connect-http-sink/security/http-service-mtls-auth.certificate.pem --key ../../connect/connect-http-sink/security/http-service-mtls-auth.key --tlsv1.2 --cacert ../../connect/connect-http-sink/security/snakeoil-ca-1.crt  -X PUT \
     -H "Content-Type: application/json" \
     --data '{"test":"value"}' \
     https://localhost:8643/api/messages | jq .



sleep 2

log "Verify we have received the data in http-topic-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic http-topic-messages --from-beginning --property print.key=true --max-messages 1


exit 0

docker exec -d --privileged --user root connect bash -c 'tcpdump -w /tmp/tcpdump.pcap -i eth0 -s 0'
