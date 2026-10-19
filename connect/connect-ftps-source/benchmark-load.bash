#!/bin/bash
# load for 'playground connector benchmark': files of json users (the records of the example) written to the
# ftps.input.path of the ftps source connector, in the home of its user on the ftps-server container (see "Benchmark"
# in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
files_format=$(benchmark_users_files_format ftps.input.file.pattern)
read -r format extension <<< "$files_format"
# vsftpd chroots each user in /home/vsftpd/<user>
user=$(jq -r '."ftps.username" // "bob"' "$BENCHMARK_CONNECTOR_CONFIG")
input_path="/home/vsftpd/$user$(jq -r '."ftps.input.path" // "/input"' "$BENCHMARK_CONNECTOR_CONFIG")"
upload_to_ftps () {
    benchmark_container_files_upload ftps-server "$input_path" "$1"
}
benchmark_files_load upload_to_ftps "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" "$format" "$extension"
