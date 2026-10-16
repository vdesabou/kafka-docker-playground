#!/bin/bash
# load for 'playground connector benchmark': json files uploaded to the topics.dir of the generalized gcs source connector
# (gcs-source-generalized.sh), with gcloud and the credentials of the gcloud-config container of the example (see
# "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
bucket=$(jq -r '."gcs.bucket.name"' "$BENCHMARK_CONNECTOR_CONFIG")
topics_dir=$(jq -r '."topics.dir" // "topics"' "$BENCHMARK_CONNECTOR_CONFIG")
if ! docker inspect gcloud-config > /dev/null 2>&1
then
    logerror "❌ no gcloud-config container (gcloud authenticated with the keyfile.json of the example): run gcs-source-generalized.sh first"
    exit 1
fi
upload_to_gcs () {
    docker run --quiet --rm -v "$PLAYGROUND_HOST_TMP_DIR/$1:/tmp/benchmark" --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage cp "/tmp/benchmark/*" "gs://$bucket/$topics_dir/" --quiet
}
benchmark_cloud_storage_load upload_to_gcs "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
