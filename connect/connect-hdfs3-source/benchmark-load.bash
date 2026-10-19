#!/bin/bash
# load for 'playground connector benchmark': avro files of {"f1":"benchmark message <i>"} records written to hdfs in the
# layout of the hdfs3 sink (<topics.dir>/<topic>/<partition>/<topic>+0+<start>+<end>.avro), read back by the hdfs3 source
# connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
benchmark_hdfs_load /opt/hadoop-3.1.3/bin/hdfs "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
