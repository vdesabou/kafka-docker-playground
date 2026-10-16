#!/bin/bash
# load for 'playground connector benchmark' and 'playground run --enable-sql-datagen': rows in the dbo.customers table
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
benchmark_sql_load sqlserver sqlserver '/opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password! -d testDB' "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
