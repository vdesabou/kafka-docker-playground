#!/bin/bash
# load for 'playground connector benchmark': json files uploaded to the topics.dir of the generalized s3 source connector
# (s3-source-generalized.sh), with the aws cli (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
bucket=$(jq -r '."s3.bucket.name"' "$BENCHMARK_CONNECTOR_CONFIG")
topics_dir=$(jq -r '."topics.dir" // "topics"' "$BENCHMARK_CONNECTOR_CONFIG")
# the aws function takes AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY or ~/.aws, like the example
AWS_REGION=$(jq -r --arg r "$AWS_REGION" '."s3.region" // $r' "$BENCHMARK_CONNECTOR_CONFIG")
upload_to_s3 () {
    aws s3 cp "/tmp/$1" "s3://$bucket/$topics_dir/" --recursive --only-show-errors --region "$AWS_REGION"
}
benchmark_cloud_storage_load upload_to_s3 "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
