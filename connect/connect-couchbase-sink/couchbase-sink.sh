#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Couchbase cluster"
playground container exec --container couchbase --command "bash -c \"/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query\""
log "Creating Couchbase bucket travel-data"
playground container exec --container couchbase --command "bash -c \"/opt/couchbase/bin/couchbase-cli bucket-create --cluster localhost:8091 --username Administrator --password password --bucket travel-data --bucket-type couchbase --bucket-ramsize 100\""

log "Sending messages to topic couchbase-sink-example"
# Ensure one CDG document exists for verification below.
playground topic produce -t couchbase-sink-example --nb-messages 1 --forced-value '{"airport":"CDG","degreesF":70,"timestamp":1735689600000}' << 'EOF'
{
     "namespace": "couchbase",
     "name": "weatherReport",
     "type": "record",
     "fields": [
          {
               "name": "airport",
               "type": {
                    "type": "string",
                    "arg.properties": {
                         "options": ["SFO", "YVR", "LHR", "CDG", "TXL", "VCE", "DME", "DEL", "BJS"]
                    }
               }
          },
          {
               "name": "degreesF",
               "type": {
                    "type": "int",
                    "arg.properties": {
                         "range": {
                              "min": 20,
                              "max": 120
                         }
                    }
               }
          },
          {
               "name": "timestamp",
               "type": {
                    "type": "long",
                    "arg.properties": {
                         "range": {
                              "min": 1574170000000,
                              "max": 1893456000000
                         }
                    }
               }
          }
     ]
}
EOF

playground topic produce -t couchbase-sink-example --nb-messages 19 << 'EOF'
{
     "namespace": "couchbase",
     "name": "weatherReport",
     "type": "record",
     "fields": [
          {
               "name": "airport",
               "type": {
                    "type": "string",
                    "arg.properties": {
                         "options": ["SFO", "YVR", "LHR", "CDG", "TXL", "VCE", "DME", "DEL", "BJS"]
                    }
               }
          },
          {
               "name": "degreesF",
               "type": {
                    "type": "int",
                    "arg.properties": {
                         "range": {
                              "min": 20,
                              "max": 120
                         }
                    }
               }
          },
          {
               "name": "timestamp",
               "type": {
                    "type": "long",
                    "arg.properties": {
                         "range": {
                              "min": 1574170000000,
                              "max": 1893456000000
                         }
                    }
               }
          }
     ]
}
EOF

log "Creating Couchbase sink connector"
playground connector create-or-update --connector couchbase-sink  << EOF
{
     "connector.class": "com.couchbase.connect.kafka.CouchbaseSinkConnector",
     "tasks.max": "2",
     "topics": "couchbase-sink-example",
     "couchbase.seed.nodes": "couchbase",
     "couchbase.bootstrap.timeout": "2000ms",
     "couchbase.bucket": "travel-data",
     "couchbase.username": "Administrator",
     "couchbase.password": "password",
     "couchbase.persist.to": "NONE",
     "couchbase.replicate.to": "NONE",
     "couchbase.document.id": "/airport",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF

sleep 10

log "Verify data is in Couchbase"
playground container exec --container couchbase --command "bash -c \"cbc cat CDG -U couchbase://localhost/travel-data -u Administrator -P password\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "airport" /tmp/result.log
