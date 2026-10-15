#!/bin/bash
# load for 'playground connector benchmark': documents in the collection of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# same mongosh options (tls) as the variant of the example that was run, database and collection of the connector
client=$(benchmark_mongo_client_from_example "$BENCHMARK_TEST_FILE")
database=$(jq -r '.database // "inventory"' "$BENCHMARK_CONNECTOR_CONFIG")
collection=$(jq -r '.collection // "customers"' "$BENCHMARK_CONNECTOR_CONFIG")
benchmark_mongo_load mongodb "$client" "$database" "$collection" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
