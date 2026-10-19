#!/bin/bash
# load for 'playground connector benchmark': log events put in the log stream of the connector with boto3
# (put_log_events of 10000 events), with the aws credentials of the playground (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
log_group=$(jq -r '."aws.cloudwatch.log.group" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
# the first stream of the connector
log_stream=$(jq -r '."aws.cloudwatch.log.streams" // empty | split(",")[0]' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$log_group" ] || [ -z "$log_stream" ]
then
    logerror "❌ aws.cloudwatch.log.group and aws.cloudwatch.log.streams must be set in the config of the connector"
    exit 1
fi
# https://logs.<region>.amazonaws.com
region=$(jq -r '."aws.cloudwatch.logs.url" // empty' "$BENCHMARK_CONNECTOR_CONFIG" | sed -n 's|^https://logs\.\([^.]*\)\..*|\1|p')
benchmark_python_load "$(benchmark_aws_docker_options)" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" \
    cloudwatch-logs --log-group "$log_group" --log-stream "$log_stream" --region "${region:-$AWS_REGION}" --threads 1
