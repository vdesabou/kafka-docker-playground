#!/bin/bash
# load for 'playground connector benchmark': csv files of musics (the dataset of csv.sh: title;album;duration;release;
# artist;type, artist U2 as the Drop filter of the example keeps only those) moved into the fs.listing.directory.path of
# the filepulse connector in the connect container (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
reader=$(jq -r '."tasks.reader.class" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
if [[ "$reader" != *RowFileInputReader ]]
then
    logerror "❌ this load writes csv rows (csv.sh): the connector reads its files with $reader (one record per file or xml), not supported"
    exit 1
fi
input_path=$(jq -r '."fs.listing.directory.path" // "/tmp/kafka-connect/examples/"' "$BENCHMARK_CONNECTOR_CONFIG")
export BENCHMARK_FILES_HEADER="title;album;duration;release;artist;type"
export BENCHMARK_FILES_ROW="{message};Benchmark;3:30;2026;U2;Rock"
upload_to_connect () {
    benchmark_container_files_upload connect "${input_path%/}" "$1"
}
benchmark_files_load upload_to_connect "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" custom csv
