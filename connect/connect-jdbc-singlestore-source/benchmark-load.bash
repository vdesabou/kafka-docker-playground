#!/bin/bash
# load for 'playground connector benchmark': rows inserted in the application table of the example (database db), read
# by the jdbc source connector in timestamp+incrementing mode (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"
if [ "$records" -gt 10000000 ]
then
    logerror "❌ this load inserts at most 10000000 rows at a time"
    exit 1
fi
BENCHMARK_SQL_TABLE="application"
# a table of ten digits joined with itself numbers the rows, up to 10^7 (the connector only reads the application table)
BENCHMARK_SQL_CREATE="CREATE TABLE IF NOT EXISTS benchmark_digits (d INT PRIMARY KEY);
REPLACE INTO benchmark_digits VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9);"
BENCHMARK_SQL_BULK="INSERT INTO application (name, team_email, last_modified) SELECT CONCAT('benchmark ', n), CONCAT('team', n, '@example.com'), NOW() FROM (SELECT 1 + a.d + 10 * b.d + 100 * c.d + 1000 * e.d + 10000 * f.d + 100000 * g.d + 1000000 * h.d AS n FROM benchmark_digits a, benchmark_digits b, benchmark_digits c, benchmark_digits e, benchmark_digits f, benchmark_digits g, benchmark_digits h) s WHERE n <= $records;"
# one statement per row, each one its own transaction (autocommit), only built for that shape
[ "$BENCHMARK_LOAD_SHAPE" == "small-txn" ] && BENCHMARK_SQL_SMALL_TXN="$(awk -v n="$records" 'BEGIN { for (i = 1; i <= n; i++) printf "INSERT INTO application (name, team_email, last_modified) VALUES (%cbenchmark %d%c, %cteam%d@example.com%c, NOW());\n", 39, i, 39, 39, i, 39 }')"
BENCHMARK_SQL_COUNT="SELECT COUNT(*) FROM application;"
BENCHMARK_SQL_COUNT_FLAGS="-N -s"
benchmark_sql_load custom singlestore "memsql -u root -proot -D db" "$records" "$BENCHMARK_LOAD_SHAPE" "$BENCHMARK_LOAD_MODE"
