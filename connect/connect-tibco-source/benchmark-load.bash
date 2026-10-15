#!/bin/bash
# load for 'playground connector benchmark': messages sent to the tibco ems destination of the connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# BenchmarkJmsProducer in the tibco-ems container, with the tibco client jars, through the jndi of the ems server
# passwords are masked by the connect rest api: benchmark_connector_config_value takes them from the example script
cfg () { benchmark_connector_config_value "$1"; }
url=$(cfg tibco.url)
benchmark_jms_load tibco-ems "/opt/tibco/ems/8.5/lib/jms-2.0.jar:/opt/tibco/ems/8.5/lib/tibjms.jar" com.tibco.tibjms.naming.TibjmsInitialContextFactory "${url/tcp:/tibjmsnaming:}" "$(cfg tibco.username)" "$(cfg tibco.password)" ConnectionFactory "$(cfg jms.destination.type)" "$(cfg jms.destination.name)" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
