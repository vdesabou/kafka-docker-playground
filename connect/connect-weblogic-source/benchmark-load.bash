#!/bin/bash
# load for 'playground connector benchmark': messages sent to the weblogic destination of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# BenchmarkJmsProducer in the jms-sender container of the example, with the weblogic client jars and the jndi settings of the connector
# passwords are masked by the connect rest api: benchmark_connector_config_value takes them from the example script
cfg () { benchmark_connector_config_value "$1"; }
benchmark_jms_load jms-sender "/tmp/weblogic.jar:/tmp/wlthint3client.jar" "$(cfg java.naming.factory.initial)" "$(cfg java.naming.provider.url)" "$(cfg java.naming.security.principal)" "$(cfg java.naming.security.credentials)" "$(cfg connection.factory.name)" "$(cfg jms.destination.type)" "$(cfg jms.destination.name)" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
