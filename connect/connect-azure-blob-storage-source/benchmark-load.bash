#!/bin/bash
# load for 'playground connector benchmark': json files uploaded to the topics.dir of the generalized azure blob storage
# source connector (azure-blob-storage-source-generalized.sh), with az and the account key of the example (see
# "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
# the example gives the account to the connector with \${file:/data:<key>}: read <key> in the data file it generated
data_file="${DIR}/../../connect/connect-azure-blob-storage-source/data"
function azure_config_value () {
    local key="$1" data_key="$2" value
    value=$(jq -r --arg k "$key" '.[$k] // empty' "$BENCHMARK_CONNECTOR_CONFIG")
    if [ -z "$value" ] || [[ "$value" == *'${file:'* ]] || [[ "$value" == *"•"* ]] || [ "$value" == "[hidden]" ] || [[ "$value" =~ ^\*+$ ]]
    then
        value=$(grep "^${data_key}=" "$data_file" 2> /dev/null | head -1 | cut -d= -f2-)
    fi
    echo "$value"
}
account_name=$(azure_config_value azblob.account.name AZURE_ACCOUNT_NAME)
account_key=$(azure_config_value azblob.account.key AZURE_ACCOUNT_KEY)
# the fully managed example writes no data file, and the ccloud connect api masks the key: ask azure for it
if [[ "$BENCHMARK_TEST_FILE" == */ccloud/* ]] && [ -n "$account_name" ]
then
    account_key=$(az storage account keys list --account-name "$account_name" --query "[0].value" -o tsv 2> /dev/null)
fi
container_name=$(azure_config_value azblob.container.name AZURE_CONTAINER_NAME)
topics_dir=$(jq -r '."topics.dir" // "topics"' "$BENCHMARK_CONNECTOR_CONFIG")
if [ -z "$account_name" ] || [ -z "$account_key" ] || [ -z "$container_name" ]
then
    logerror "❌ the storage account of the connector is not in its config nor in $data_file: run azure-blob-storage-source-generalized.sh first"
    exit 1
fi
upload_to_azure () {
    az storage blob upload-batch --account-name "$account_name" --account-key "$account_key" --destination "$container_name" --destination-path "$topics_dir" --source "/tmp/$1" --only-show-errors > /dev/null
}
benchmark_cloud_storage_load upload_to_azure "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE"
