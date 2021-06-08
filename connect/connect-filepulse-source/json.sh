#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Generating data"
docker exec -i connect bash << EOFCONNECT
mkdir -p /tmp/kafka-connect/examples/
cat <<EOF > /tmp/kafka-connect/examples/track.json
{
  "track": {
     "title":"Star Wars (Main Theme)",
     "artist":"John Williams, London Symphony Orchestra",
     "album":"Star Wars",
     "duration":"10:52"
  }
}
EOF
EOFCONNECT


log "Creating JSON FilePulse Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
            "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
            "fs.scan.directory.path":"/tmp/kafka-connect/examples/",
            "fs.scan.interval.ms":"10000",
            "fs.scan.filters":"io.streamthoughts.kafka.connect.filepulse.scanner.local.filter.RegexFileListFilter",
            "file.filter.regex.pattern":".*\\.json$",
            "task.reader.class": "io.streamthoughts.kafka.connect.filepulse.reader.BytesArrayInputReader",
            "offset.strategy":"name",
            "topic":"tracks-filepulse-json-00",
            "internal.kafka.reporter.bootstrap.servers": "broker:9092",
            "internal.kafka.reporter.topic":"connect-file-pulse-status",
            "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.clean.DeleteCleanupPolicy",
            "filters": "ParseJSON",
            "filters.ParseJSON.type":"io.streamthoughts.kafka.connect.filepulse.filter.JSONFilter",
            "filters.ParseJSON.source":"message",
            "filters.ParseJSON.merge":"true",
            "tasks.max": 1
          }' \
     http://localhost:8083/connectors/filepulse-source-json/config | jq .


sleep 5

log "Verify we have received the data in tracks-filepulse-json-00 topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracks-filepulse-json-00 --from-beginning --max-messages 1