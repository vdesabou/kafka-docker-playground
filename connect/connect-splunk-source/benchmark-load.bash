#!/bin/bash
# load for 'playground connector benchmark': events sent to the http event collector of the connector, --mode steady only (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
port=$(jq -r '."splunk.port" // "8889"' "$BENCHMARK_CONNECTOR_CONFIG")
benchmark_splunk_load "https://localhost:$port/services/collector/event" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
