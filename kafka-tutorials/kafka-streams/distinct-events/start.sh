#!/bin/bash

# https://kafka-tutorials.confluent.io/filter-a-stream-of-events/kstreams.html

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

echo -e "\n\n⏳ Waiting for Schema Registry to be available\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) -eq 000 ]
do
  echo -e $(date) "Schema Registry HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) " (waiting for 200)"
  sleep 5
done

echo -e "\033[0;33mProduce sample clicks\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic clicks --broker-list broker:9092 --property value.schema="$(< src/main/avro/click.avsc)" << EOF
{"ip":"10.0.0.1","url":"https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html","timestamp":"2019-09-16T14:53:43+00:00"}
{"ip":"10.0.0.2","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:01"}
{"ip":"10.0.0.3","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:03"}
{"ip":"10.0.0.1","url":"https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html","timestamp":"2019-09-16T14:53:43+00:00"}
{"ip":"10.0.0.2","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:01"}
{"ip":"10.0.0.3","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:03"}
EOF

echo -e "\033[0;33mConsume distinct events from the output topic\033[0m"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic distinct-clicks --bootstrap-server broker:9092 --from-beginning --max-messages 3
