validate_client_version() {
  # java: an Apache Kafka version (3.7.1); client examples: the version of their Confluent client (2.6.0, v2.6.0…)
  if [[ ! "$1" =~ ^v?[0-9]+(\.[0-9]+)+([.+_-][0-9A-Za-z.+_-]+)?$ ]]
  then
    echo "must be a version like 3.7.1 (java examples: the version of org.apache.kafka:kafka-clients; client examples: the version of their client, see their README)"
  fi
}
