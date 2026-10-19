#!/bin/bash
# load for 'playground connector benchmark': messages published to the pub/sub topic of the connector with the python
# client (batches of 1000 messages), with the keyfile.json of the example (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
project=$(jq -r '."cps.project" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
topic=$(jq -r '."cps.topic" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
keyfile="${DIR}/../../connect/connect-gcp-google-pubsub-source/keyfile.json"
if [ -z "$project" ] || [ -z "$topic" ] || [ ! -f "$keyfile" ]
then
    logerror "❌ cps.project / cps.topic are not in the config of the connector, or $keyfile does not exist: run gcp-google-pubsub-source.sh first"
    exit 1
fi
benchmark_python_load "-v $keyfile:/tmp/keyfile.json:ro" "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" \
    pubsub --project "$project" --topic "$topic" --keyfile /tmp/keyfile.json
