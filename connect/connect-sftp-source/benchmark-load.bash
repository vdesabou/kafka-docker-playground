#!/bin/bash
# load for 'playground connector benchmark': files of users (the records of the examples) written to the input.path of
# the sftp source connector, in the format of its connector class: json lines, or csv / tsv with csv.separator.char and
# csv.first.row.as.header (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
files_format=$(benchmark_users_files_format input.file.pattern)
read -r format extension <<< "$files_format"
# the server of the example (sftp-server, ssh-server for kerberos), with a chroot or not
container=$(jq -r '."sftp.host" // "sftp-server"' "$BENCHMARK_CONNECTOR_CONFIG")
input_path=$(jq -r '."input.path"' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$BENCHMARK_LOAD_CHECK" ] && playground --output-level ERROR container exec --container "$container" --root --command "test -d /chroot$input_path" > /dev/null 2>&1
then
    input_path="/chroot$input_path"
fi
upload_to_sftp () {
    benchmark_container_files_upload "$container" "$input_path" "$1"
}
benchmark_files_load upload_to_sftp "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" "$format" "$extension"
