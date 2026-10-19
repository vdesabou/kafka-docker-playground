#!/bin/bash
# load for 'playground connector benchmark': messages sent to the sqs queue of the connector with boto3 (batches of 10
# messages from 16 threads), with the aws credentials of the playground (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
queue_url=$(jq -r '."sqs.url" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$queue_url" ]
then
    logerror "❌ no sqs.url in the config of the connector"
    exit 1
fi
# https://sqs.<region>.amazonaws.com/<account>/<queue>
region=$(echo "$queue_url" | sed -n 's|^https://sqs\.\([^.]*\)\..*|\1|p')
benchmark_python_load "$(benchmark_aws_docker_options)" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" \
    sqs --queue-url "$queue_url" --region "${region:-$AWS_REGION}"
