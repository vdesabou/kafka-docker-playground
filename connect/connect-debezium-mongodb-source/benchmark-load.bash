#!/bin/bash
# load for 'playground connector benchmark': documents inserted in the inventory.customers collection of the examples,
# captured by the debezium mongodb connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# mongosh with the tls options of the ssl variant
client=$(benchmark_mongo_client_from_example "$BENCHMARK_TEST_FILE")
# the first collection of collection.include.list (<database>.<collection>), inventory.customers by default
included=$(jq -r '."collection.include.list" // "inventory.customers" | split(",")[0]' "$BENCHMARK_CONNECTOR_CONFIG")
benchmark_mongo_load mongodb "$client" "${included%%.*}" "${included#*.}" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
