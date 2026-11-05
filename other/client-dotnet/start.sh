#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-dotnet container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-dotnet

NB_MESSAGES=10

log "Creating topics dotnet-string and dotnet-avro"
playground topic create --topic dotnet-string --nb-partitions 3
playground topic create --topic dotnet-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the .NET producer"
playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll produce dotnet-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the .NET consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll consume dotnet-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the .NET producer (AvroSerializer, schema registered under subject dotnet-avro-value)"
playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll produce-avro dotnet-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the .NET consumer (AvroDeserializer)"
playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll consume-avro dotnet-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the .NET AvroSerializer under subject dotnet-avro-value"
playground schema get --subject dotnet-avro-value

log "Checking the consumer groups of the .NET consumer committed the offsets"
playground consumer-group describe --group dotnet-string-group
playground consumer-group describe --group dotnet-avro-group
