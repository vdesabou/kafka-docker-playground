#!/bin/bash

# https://kafka-tutorials.confluent.io/create-stateful-aggregation-sum/kstreams.html

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

echo -e "\033[0;33mProduce events to the input topic\033[0m"
docker exec -i schema-registry /usr/bin/kafka-avro-console-producer --topic movie-ticket-sales --broker-list broker:9092 --property value.schema="$(< src/main/avro/ticket-sale.avsc)" << EOF
{"title":"Die Hard","sale_ts":"2019-07-18T10:00:00Z","ticket_total_value":12}
{"title":"Die Hard","sale_ts":"2019-07-18T10:01:00Z","ticket_total_value":12}
{"title":"The Godfather","sale_ts":"2019-07-18T10:01:31Z","ticket_total_value":12}
{"title":"Die Hard","sale_ts":"2019-07-18T10:01:36Z","ticket_total_value":24}
{"title":"The Godfather","sale_ts":"2019-07-18T10:02:00Z","ticket_total_value":18}
{"title":"The Big Lebowski","sale_ts":"2019-07-18T11:03:21Z","ticket_total_value":12}
{"title":"The Big Lebowski","sale_ts":"2019-07-18T11:03:50Z","ticket_total_value":12}
{"title":"The Godfather","sale_ts":"2019-07-18T11:40:00Z","ticket_total_value":36}
{"title":"The Godfather","sale_ts":"2019-07-18T11:40:09Z","ticket_total_value":18}
EOF

echo -e "\033[0;33mConsume aggregated sum from the output topic\033[0m"
docker exec -it broker /usr/bin/kafka-console-consumer --topic movie-revenue --bootstrap-server broker:9092 --from-beginning --property print.key=true --property value.deserializer=org.apache.kafka.common.serialization.IntegerDeserializer --max-messages 9