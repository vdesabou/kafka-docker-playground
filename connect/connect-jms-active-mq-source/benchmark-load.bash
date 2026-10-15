#!/bin/bash
# load for 'playground connector benchmark': messages sent to the activemq destination of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
destination_type=$(jq -r '."jms.destination.type" // "queue"' "$BENCHMARK_CONNECTOR_CONFIG")
destination=$(jq -r '."jms.destination.name"' "$BENCHMARK_CONNECTOR_CONFIG")
# broker admin user of the example
benchmark_activemq_load activemq admin admin "$destination_type" "$destination" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
