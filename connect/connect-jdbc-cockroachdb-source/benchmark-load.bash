#!/bin/bash
# load for 'playground connector benchmark': rows inserted in the drivers table of the example, read by the jdbc source
# connector in incrementing mode on rownum (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"
BENCHMARK_SQL_TABLE="drivers"
BENCHMARK_SQL_BULK="INSERT INTO drivers (id, city, name, dl, address) SELECT gen_random_uuid(), 'city' || (i % 10)::STRING, 'driver ' || i::STRING, 'DL-' || i::STRING, i::STRING || ' benchmark street' FROM generate_series(1, $records) AS g(i);"
# no procedural loop in cockroachdb: one statement per row, each one its own transaction, only built for that shape
[ "$BENCHMARK_LOAD_SHAPE" == "small-txn" ] && BENCHMARK_SQL_SMALL_TXN="$(awk -v n="$records" 'BEGIN { for (i = 1; i <= n; i++) printf "INSERT INTO drivers (id, city, name, dl, address) VALUES (gen_random_uuid(), %c%s%d%c, %cdriver %d%c, %cDL-%d%c, %c%d benchmark street%c);\n", 39, "city", i % 10, 39, 39, i, 39, 39, i, 39, 39, i, 39 }')"
# incrementing mode: updates and deletes are not captured
BENCHMARK_SQL_COUNT="SELECT COUNT(*) FROM drivers;"
BENCHMARK_SQL_COUNT_FLAGS="--format=csv"
benchmark_sql_load custom cockroachdb "/cockroach/cockroach sql --insecure" "$records" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
