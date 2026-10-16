#!/bin/bash
# load for 'playground connector benchmark' (BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash) and --enable-sql-datagen:
# rows in the orders table of postgres-orders.sh, a table of your own (see "A table of your own" in the documentation)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

# --records <n> --mode preload|stream --shape bulk|small-txn|update [--check]
benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"

# --check: called before the connector is paused, refuse what this load cannot do
if [ -n "$BENCHMARK_LOAD_CHECK" ]
then
  if [ "$BENCHMARK_LOAD_SHAPE" == "update" ]
  then
    # the connector of postgres-orders.sh is in incrementing mode: it only captures new rows
    logerror "❌ this load only inserts rows (the connector is in incrementing mode): use --shape bulk or small-txn"
    exit 1
  fi
  exit 0
fi

case "$BENCHMARK_LOAD_SHAPE" in
  bulk)
    # one transaction with all the rows
    sql="INSERT INTO orders (customer_id, product, quantity, price) SELECT i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2) FROM generate_series(1, $records) AS i;"
  ;;
  small-txn)
    # one transaction per row
    sql="DO \$\$ BEGIN FOR i IN 1..$records LOOP INSERT INTO orders (customer_id, product, quantity, price) VALUES (i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2)); COMMIT; END LOOP; END \$\$;"
  ;;
esac

function load_batch () {
  echo "$sql" | playground container exec --container postgres --command "psql -U myuser -d postgres" > /dev/null
}

if [ "$BENCHMARK_LOAD_MODE" == "stream" ]
then
  # steady mode: batches of <records> rows until the benchmark creates $BENCHMARK_STOP_FILE
  benchmark_stream_batches "$records" load_batch
else
  # drain: load the backlog, and tell the benchmark how many records the connector should write
  load_batch
  echo "BENCHMARK_RECORDS=$records"
fi
