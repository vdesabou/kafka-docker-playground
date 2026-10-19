#!/bin/bash
# load for 'playground connector benchmark': rows inserted in the conditions hypertable of the example (time, location,
# temperature, humidity), captured by debezium from the chunks of _timescaledb_internal (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"
row="now() - make_interval(secs => i / 1000.0), 'city' || (i % 100), 20 + random() * 15, 40 + random() * 50"
BENCHMARK_SQL_TABLE="conditions"
BENCHMARK_SQL_BULK="INSERT INTO conditions (time, location, temperature, humidity) SELECT $row FROM generate_series(1, $records) AS i;"
BENCHMARK_SQL_SMALL_TXN="DO \$\$ BEGIN FOR i IN 1..$records LOOP INSERT INTO conditions (time, location, temperature, humidity) SELECT $row; COMMIT; END LOOP; END \$\$;"
# the hypertable has no key: no update nor delete of exactly <records> rows
BENCHMARK_SQL_COUNT="SELECT COUNT(*) FROM conditions;"
BENCHMARK_SQL_COUNT_FLAGS="-t -A"
benchmark_sql_load custom timescaledb "psql -U postgres -d postgres" "$records" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
