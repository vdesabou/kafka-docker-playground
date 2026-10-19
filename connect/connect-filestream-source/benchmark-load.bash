#!/bin/bash
# load for 'playground connector benchmark': json lines appended to the file tailed by the filestream source connector
# in the connect container (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
file=$(jq -r '.file // empty' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$file" ]
then
    logerror "❌ no file in the config of the connector"
    exit 1
fi
benchmark_append_file_load connect "$file" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
