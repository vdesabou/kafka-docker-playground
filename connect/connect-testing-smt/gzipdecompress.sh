#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# GzipDecompress needs the record value to be a real byte[] of gzip data. ByteArrayConverter is the
# only converter that guarantees a byte[] (a datagen Struct or a Debezium bytea/ByteBuffer would fail
# GzipDecompress's hard (byte[]) cast). Verification is functional only: valid gzip in => records flow;
# a broken/incompatible SMT throws under errors.tolerance=none => 0 records => test red. The
# decompressed content itself can't be read back (the HTTP sink stringifies a byte[] value as [B@...).

# The HTTP sink connector needs jcl-over-slf4j on its classpath
cd ${DIR}
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
mkdir -p ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cp ${DIR}/jcl-over-slf4j-2.0.7.jar ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cd - > /dev/null

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# 1. Build the gzip payload on the host (gzip -n keeps it deterministic; content is irrelevant to the test)
GZ=/tmp/smt-gzip-payload.gz
printf '%s' "GZIP_DECOMPRESSED_PAYLOAD" | gzip -c -n > "$GZ"

# 2. Pick a delimiter byte (1-255) that does NOT occur in the gzip file, so kcat produces the whole
#    file as a SINGLE message instead of splitting it on the default newline (gzip contains 0x0A).
present=$(od -An -tu1 -v "$GZ" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un)
delim_dec=""
for b in $(seq 1 255)
do
     # skip backslash (92) so kcat can't treat the delimiter as an escape
     if [ "$b" -eq 92 ]; then continue; fi
     if ! echo "$present" | grep -qx "$b"; then delim_dec="$b"; break; fi
done
if [ -z "$delim_dec" ]; then logerror "❌ could not find a delimiter byte absent from the gzip payload"; exit 1; fi
delim_byte=$(printf "\\$(printf '%03o' "$delim_dec")")
log "Using absent byte $delim_dec (0x$(printf '%02x' "$delim_dec")) as the kcat message delimiter"

# 3. Produce the gzip bytes as one message to topic gzip-input. Attach kcat to the broker's docker
#    network and use the internal listener broker:9092 (portable across Linux/macOS Docker).
network=$(docker inspect broker --format '{{range $k,$_ := .NetworkSettings.Networks}}{{$k}}{{end}}')
log "Producing the gzip payload as a single message to topic gzip-input (kcat on network $network)"
docker run -i --rm --network "$network" --entrypoint kcat confluentinc/cp-kcat:latest \
     -b broker:9092 -t gzip-input -P -D "$delim_byte" < "$GZ"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector (ByteArrayConverter) with the Confluent GzipDecompress SMT (io.confluent.connect.transforms) decompressing the gzip value"
playground connector create-or-update --connector http-sink  << EOF
{
     "topics": "gzip-input",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
     "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "reporter.result.topic.value.format": "string",
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "string",
     "headers": "Content-Type: text/plain",

     "transforms": "gzipDecompress",
     "transforms.gzipDecompress.type": "io.confluent.connect.transforms.GzipDecompress\$Value"
}
EOF

sleep 10

log "Check the success-responses topic: the gzip record was decompressed by the SMT and flowed to the HTTP server"
playground topic consume --topic success-responses --min-expected-messages 1 --timeout 60
