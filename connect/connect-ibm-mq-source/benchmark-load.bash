#!/bin/bash
# load for 'playground connector benchmark': messages put in the ibm mq queue of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# queue manager and queue of the connector
queue_manager=$(jq -r '."mq.queue.manager" // "QM1"' "$BENCHMARK_CONNECTOR_CONFIG")
queue=$(jq -r '."jms.destination.name" // "DEV.QUEUE.1"' "$BENCHMARK_CONNECTOR_CONFIG")
benchmark_ibmmq_load ibmmq "$queue_manager" "$queue" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
