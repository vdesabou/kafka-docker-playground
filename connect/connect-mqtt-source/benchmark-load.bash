#!/bin/bash
# load for 'playground connector benchmark': messages published to the mqtt topic of the connector, --mode steady only (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# topic (wildcards replaced), qos and credentials of the connector
topic=$(jq -r '."mqtt.topics" | split(",")[0] | gsub("[#+]"; "benchmark")' "$BENCHMARK_CONNECTOR_CONFIG")
qos=$(jq -r '."mqtt.qos" // "1"' "$BENCHMARK_CONNECTOR_CONFIG")
user=$(benchmark_connector_config_value mqtt.username)
password=$(benchmark_connector_config_value mqtt.password)
options="-h localhost -p 1883"
if [[ "$BENCHMARK_TEST_FILE" == *mtls* ]]
then
    # same certificates as the mtls variant of the example
    options="-h localhost -p 8883 --cafile /etc/mosquitto/certs/ca.crt --key /etc/mosquitto/certs/server.key --cert /etc/mosquitto/certs/server.crt"
fi
if [ -n "$user" ]
then
    options="$options -u \"$user\" -P \"$password\""
fi
benchmark_mqtt_load mosquitto "$options" "$topic" "$qos" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
