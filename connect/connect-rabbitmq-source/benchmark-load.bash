#!/bin/bash
# load for 'playground connector benchmark': messages published to the rabbitmq queue of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
queue=$(jq -r '."rabbitmq.queue"' "$BENCHMARK_CONNECTOR_CONFIG")
# rabbitmq_producer in the fully managed example
producer=rabbitmq-producer
if ! docker inspect "$producer" > /dev/null 2>&1 && docker inspect rabbitmq_producer > /dev/null 2>&1
then
    producer=rabbitmq_producer
fi
benchmark_rabbitmq_load "$producer" "$queue" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_MODE"
