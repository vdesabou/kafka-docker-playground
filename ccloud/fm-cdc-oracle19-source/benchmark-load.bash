#!/bin/bash
# load for 'playground connector benchmark' and 'playground run --enable-sql-datagen': rows in the CUSTOMERS table
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# same database user and container (cdb or pdb) as the variant of the example that was run
client=$(benchmark_oracle_client_from_example "$BENCHMARK_TEST_FILE")
# with redo.log.topic.name, each row change is written twice (redo log topic and table topic), and each commit
# once more to the redo log topic
if [ -f "$BENCHMARK_CONNECTOR_CONFIG" ] && [ -n "$(jq -r '."redo.log.topic.name" // empty' "$BENCHMARK_CONNECTOR_CONFIG")" ]
then
    export BENCHMARK_RECORDS_PER_CHANGE=2
    export BENCHMARK_RECORDS_PER_TRANSACTION=1
fi
benchmark_sql_load oracle oracle "$client" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
