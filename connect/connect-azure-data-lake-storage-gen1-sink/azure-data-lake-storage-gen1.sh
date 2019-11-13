#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "az"

if [ -z "$1" ]
then
    echo "ERROR: AZURE_DATALAKE_CLIENT_ID has not been provided. Usage: azure-data-lake-storage-gen1.sh <AZURE_DATALAKE_CLIENT_ID> <AZURE_DATALAKE_CLIENT_KEY> <AZURE_DATALAKE_ACCOUNT_NAME> <AZURE_DATALAKE_TOKEN_ENDPOINT>"
    exit 1
fi

if [ -z "$2" ]
then
    echo "ERROR: AZURE_DATALAKE_CLIENT_KEY has not been provided. Usage: azure-data-lake-storage-gen1.sh <AZURE_DATALAKE_CLIENT_ID> <AZURE_DATALAKE_CLIENT_KEY> <AZURE_DATALAKE_ACCOUNT_NAME> <AZURE_DATALAKE_TOKEN_ENDPOINT>"
    exit 1
fi

if [ -z "$3" ]
then
    echo "ERROR: AZURE_DATALAKE_ACCOUNT_NAME has not been provided. Usage: azure-data-lake-storage-gen1.sh <AZURE_DATALAKE_CLIENT_ID> <AZURE_DATALAKE_CLIENT_KEY> <AZURE_DATALAKE_ACCOUNT_NAME> <AZURE_DATALAKE_TOKEN_ENDPOINT>"
    exit 1
fi

if [ -z "$4" ]
then
    echo "ERROR: AZURE_DATALAKE_TOKEN_ENDPOINT has not been provided. Usage: azure-data-lake-storage-gen1.sh <AZURE_DATALAKE_CLIENT_ID> <AZURE_DATALAKE_CLIENT_KEY> <AZURE_DATALAKE_ACCOUNT_NAME> <AZURE_DATALAKE_TOKEN_ENDPOINT>"
    exit 1
fi

read -p "Azure account: " AZ_USER && read -sp "Azure password: " AZ_PASS && echo && az login -u "$AZ_USER" -p "$AZ_PASS"

AZURE_DATALAKE_CLIENT_ID="${1}"
AZURE_DATALAKE_CLIENT_KEY="${2}"
AZURE_DATALAKE_ACCOUNT_NAME="${3}"
AZURE_DATALAKE_TOKEN_ENDPOINT="${4}"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating Data Lake Storage Gen1 Sink connector"
docker exec -e AZURE_DATALAKE_CLIENT_ID="$AZURE_DATALAKE_CLIENT_ID" -e AZURE_DATALAKE_CLIENT_KEY="$AZURE_DATALAKE_CLIENT_KEY" -e AZURE_DATALAKE_ACCOUNT_NAME="$AZURE_DATALAKE_ACCOUNT_NAME" -e AZURE_DATALAKE_TOKEN_ENDPOINT="$AZURE_DATALAKE_TOKEN_ENDPOINT" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "azure-datalake-gen1-sink3",
               "config": {
                    "connector.class": "io.confluent.connect.azure.datalake.gen1.AzureDataLakeGen1StorageSinkConnector",
                    "tasks.max": "1",
                    "topics": "datalake_topic",
                    "flush.size": "3",
                    "azure.datalake.client.id": "'"$AZURE_DATALAKE_CLIENT_ID"'",
                    "azure.datalake.client.key": "'"$AZURE_DATALAKE_CLIENT_KEY"'",
                    "azure.datalake.account.name": "'"$AZURE_DATALAKE_ACCOUNT_NAME"'",
                    "azure.datalake.token.endpoint": "'"$AZURE_DATALAKE_TOKEN_ENDPOINT"'",
                    "format.class": "io.confluent.connect.azure.storage.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic datalake_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic datalake_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 20

echo "Listing ${AZURE_DATALAKE_ACCOUNT_NAME} in Azure Data Lake"
az dls fs list --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --path /topics

rm -f /tmp/datalake_topic+0+0000000000.avro
echo "Getting one of the avro files locally and displaying content with avro-tools"
az dls fs download --account "${AZURE_DATALAKE_ACCOUNT_NAME}" --source-path /topics/datalake_topic/partition=0/datalake_topic+0+0000000000.avro --destination-path /tmp/datalake_topic+0+0000000000.avro

# brew install avro-tools
avro-tools tojson /tmp/datalake_topic+0+0000000000.avro