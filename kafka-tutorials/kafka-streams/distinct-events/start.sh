#!/bin/bash

# https://kafka-tutorials.confluent.io/filter-a-stream-of-events/kstreams.html

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d --build

echo -e "\n\n⏳ Waiting for Schema Registry to be available\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) -eq 000 ]
do
  echo -e $(date) "Schema Registry HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8081/) " (waiting for 200)"
  sleep 5
done

echo "Produce sample clicks"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic clicks --broker-list broker:9092 --property value.schema="$(< src/main/avro/click.avsc)" << EOF
{"ip":"10.0.0.1","url":"https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html","timestamp":"2019-09-16T14:53:43+00:00"}
{"ip":"10.0.0.2","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:01"}
{"ip":"10.0.0.3","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:03"}
{"ip":"10.0.0.1","url":"https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html","timestamp":"2019-09-16T14:53:43+00:00"}
{"ip":"10.0.0.2","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:01"}
{"ip":"10.0.0.3","url":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","timestamp":"2019-09-16T14:53:43+00:03"}
EOF

echo "Consume distinct events from the output topic"
docker exec -it schema-registry /usr/bin/kafka-avro-console-consumer --topic distinct-clicks --bootstrap-server broker:9092 --from-beginning --max-messages 3
