#!/bin/bash
# load for 'playground connector benchmark': records put in the kinesis stream of the connector with boto3 (put_records
# of 500 records, the throttled ones sent again), with the aws credentials of the playground (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
stream=$(jq -r '."kinesis.stream" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
region=$(jq -r --arg r "$AWS_REGION" '."kinesis.region" // $r' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$stream" ]
then
    logerror "❌ no kinesis.stream in the config of the connector"
    exit 1
fi
# a shard takes 1000 records/s: a few threads are enough for the one shard of the example
benchmark_python_load "$(benchmark_aws_docker_options)" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" \
    kinesis --stream "$stream" --region "$region" --threads 4
