#!/bin/bash
# load for 'playground connector benchmark': json messages sent to the activemq destination of the kcql of the lenses
# jms source connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# INSERT INTO <kafka topic> SELECT * FROM <destination> WITHTYPE QUEUE|TOPIC ...
kcql=$(jq -r '."connect.jms.kcql" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
destination=$(echo "$kcql" | sed -n -E 's/.*[Ff][Rr][Oo][Mm][[:space:]]+([^[:space:]]+).*/\1/p')
destination_type=$(echo "$kcql" | sed -n -E 's/.*WITHTYPE[[:space:]]+([A-Za-z]+).*/\1/p')
if [ -z "$destination" ]
then
    logerror "❌ no FROM <destination> in connect.jms.kcql: $kcql"
    exit 1
fi
# a json converter in the kcql (JsonSimpleConverter in the example) needs json messages: the fields of the message of the
# example, so that the schema registered for the kafka topic stays compatible
if echo "$kcql" | grep -q -i "WITHCONVERTER=.*Json"
then
    export BENCHMARK_JMS_JSON='{"u_name": "{message}", "u_price": 2.75, "u_quantity": 3}'
fi
benchmark_activemq_load activemq admin admin "$(echo "${destination_type:-QUEUE}" | tr '[:upper:]' '[:lower:]')" "$destination" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
