#!/bin/bash
# load for 'playground connector benchmark': files of users (the records of the examples) moved into the input.path of
# the spool dir connector in the connect container, in the format of its connector class: json lines, or csv / tsv with
# csv.separator.char and csv.first.row.as.header (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
files_format=$(benchmark_users_files_format input.file.pattern)
read -r format extension <<< "$files_format"
input_path=$(jq -r '."input.path"' "$BENCHMARK_CONNECTOR_CONFIG")
upload_to_connect () {
    benchmark_container_files_upload connect "$input_path" "$1"
}
benchmark_files_load upload_to_connect "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" "$format" "$extension"
