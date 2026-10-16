#!/bin/bash
# load for 'playground connector benchmark' and 'playground run --enable-sql-datagen': rows in the CUSTOMERS table of mydb
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
benchmark_sql_load mysql mysql "mysql --protocol=TCP --host=127.0.0.1 --user=root --password=password --database=mydb" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
