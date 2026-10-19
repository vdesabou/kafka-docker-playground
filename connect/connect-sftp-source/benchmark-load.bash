#!/bin/bash
# load for 'playground connector benchmark': files of users (the records of the examples) written to the input.path of
# the sftp source connector, in the format of its connector class: json lines, or csv / tsv with csv.separator.char and
# csv.first.row.as.header (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
connector_class=$(jq -r '."connector.class" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
case "$connector_class" in
    *SftpSchemaLessJsonSourceConnector|*SftpJsonSourceConnector)
        format="users-json"
        ;;
    *SftpCsvSourceConnector)
        separator=$(jq -r '."csv.separator.char" // "44"' "$BENCHMARK_CONNECTOR_CONFIG")
        header=$(jq -r '."csv.first.row.as.header" // "false"' "$BENCHMARK_CONNECTOR_CONFIG")
        format="users-csv:$separator:$header"
        ;;
    *)
        logerror "❌ this load writes json or csv files: $connector_class is not supported"
        exit 1
        ;;
esac
# an extension that input.file.pattern accepts (a java regex matching the whole name, the same as grep -E -x here)
pattern=$(jq -r '."input.file.pattern" // ".*"' "$BENCHMARK_CONNECTOR_CONFIG")
extension=""
for candidate in json csv tsv txt
do
    if echo "zz-benchmark-1-000001-1-000000.$candidate" | grep -q -E -x -- "$pattern"
    then
        extension="$candidate"
        break
    fi
done
if [ -z "$extension" ]
then
    logerror "❌ input.file.pattern $pattern accepts no file name of this load (zz-benchmark-<...>.json|csv|tsv|txt): use a pattern like .*\\.csv"
    exit 1
fi

# the server of the example (sftp-server, ssh-server for kerberos), with a chroot or not
container=$(jq -r '."sftp.host" // "sftp-server"' "$BENCHMARK_CONNECTOR_CONFIG")
user=$(jq -r '."sftp.username" // "foo"' "$BENCHMARK_CONNECTOR_CONFIG")
input_path=$(jq -r '."input.path"' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$BENCHMARK_LOAD_CHECK" ]
then
    if playground --output-level ERROR container exec --container "$container" --root --command "test -d /chroot$input_path" > /dev/null 2>&1
    then
        input_path="/chroot$input_path"
    fi
fi
staging_parent=$(dirname "$input_path")
# copied next to the input folder first, then moved into it: the connector never sees a file being written
upload_to_sftp () {
    local staging="$staging_parent/.benchmark-$1"
    playground --output-level ERROR container cp --source "$PLAYGROUND_HOST_TMP_DIR/$1" --destination "$container:$staging" > /dev/null
    playground --output-level ERROR container exec --container "$container" --root --command "chown -R $user $staging && mv $staging/* $input_path/ && rmdir $staging" > /dev/null
}
benchmark_files_load upload_to_sftp "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" "$format" "$extension"
