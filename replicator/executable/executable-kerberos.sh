#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-kerberos/start.sh "${PWD}/docker-compose.mdc-kerberos.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer.config /etc/kafka/producer-europe.properties'

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-us:9092 --topic sales_US --producer.config /etc/kafka/producer-us.properties'

log "Starting replicator instances"
docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f docker-compose.mdc-kerberos.replicator.yml up -d

docker container exec -i replicator-us bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
docker container exec -i replicator-europe bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'

../../scripts/wait-for-connect-and-controlcenter.sh replicator-us $@
../../scripts/wait-for-connect-and-controlcenter.sh replicator-europe $@

log "Verify we have received the data in all the sales_ topics in EUROPE"
timeout 60 docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-europe.properties'

log "Verify we have received the data in all the sales_ topics in the US"
timeout 60 docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-us.properties'
