#!/bin/bash
# load for 'playground connector benchmark' and 'playground run --enable-sql-datagen': rows in the CUSTOMERS table
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# same database user and container (cdb or pdb) as the variant of the example that was run
client=$(benchmark_oracle_client_from_example "$BENCHMARK_TEST_FILE")
benchmark_sql_load oracle oracle "$client" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
