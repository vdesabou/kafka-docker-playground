#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CERTS_DIR="${DIR}/ssl-certs"
TRUSTSTORE_PASSWORD="changeit"

log "Cleaning up previous certs"
rm -rf "${CERTS_DIR}"
mkdir -p "${CERTS_DIR}"

log "Generating self-signed CA"
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "${CERTS_DIR}/mongo-ca.key" \
  -out "${CERTS_DIR}/mongo-ca.crt" \
  -subj "/CN=mongo-ca"

log "Generating MongoDB server cert (CN=mongodb) signed by CA"
openssl req -newkey rsa:4096 -nodes \
  -keyout "${CERTS_DIR}/mongo-server.key" \
  -out "${CERTS_DIR}/mongo-server.csr" \
  -subj "/CN=mongodb"

cat > "${CERTS_DIR}/server.ext" << EOF
subjectAltName = DNS:mongodb,DNS:localhost,IP:127.0.0.1
EOF

openssl x509 -req -sha256 -days 3650 \
  -in "${CERTS_DIR}/mongo-server.csr" \
  -CA "${CERTS_DIR}/mongo-ca.crt" \
  -CAkey "${CERTS_DIR}/mongo-ca.key" \
  -CAcreateserial \
  -extfile "${CERTS_DIR}/server.ext" \
  -out "${CERTS_DIR}/mongo-server.crt"

log "Combining server cert+key into PEM (required by mongod --tlsCertificateKeyFile)"
cat "${CERTS_DIR}/mongo-server.crt" "${CERTS_DIR}/mongo-server.key" > "${CERTS_DIR}/mongo-server.pem"

log "Creating JKS truststore from CA cert"
rm -f "${CERTS_DIR}/mongo-truststore.jks"
keytool -importcert -noprompt \
  -alias mongo-ca \
  -file "${CERTS_DIR}/mongo-ca.crt" \
  -keystore "${CERTS_DIR}/mongo-truststore.jks" \
  -storepass "${TRUSTSTORE_PASSWORD}"

# Public material is world-readable; anything containing a private key stays 0600.
# *.key files are intentionally NOT chmodded — openssl writes them 0600 by default.
chmod 644 "${CERTS_DIR}"/*.crt "${CERTS_DIR}"/*.jks
chmod 600 "${CERTS_DIR}"/*.key "${CERTS_DIR}/mongo-server.pem"

export MONGODB_SSL_CERTS_DIR="${CERTS_DIR}"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssl.yml"

log "Initialize MongoDB replica set (TLS)"
docker exec -i mongodb mongosh \
  --tls --tlsCAFile /etc/ssl/mongo/mongo-ca.crt \
  --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh \
  --tls --tlsCAFile /etc/ssl/mongo/mongo-ca.crt << EOF
use admin
db.createUser(
{
user: "debezium",
pwd: "dbz",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Insert a record"
docker exec -i mongodb mongosh \
  --tls --tlsCAFile /etc/ssl/mongo/mongo-ca.crt << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh \
  --tls --tlsCAFile /etc/ssl/mongo/mongo-ca.crt << EOF
use inventory
db.customers.find().pretty();
EOF

log "Creating Debezium MongoDB source connector with TLS"
# NOTE: hardcoded credentials below are throwaway test values for a self-signed
# local TLS stack only. Never inline real credentials into a heredoc like this —
# they would end up in playground/Connect logs.
playground connector create-or-update --connector debezium-mongodb-source-ssl  << EOF
{
    "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
    "tasks.max" : "1",
    "mongodb.connection.string": "mongodb://mongodb:27017/?replicaSet=debezium",
    "topic.prefix": "dbserver1ssl",
    "mongodb.user" : "debezium",
    "mongodb.password" : "dbz",
    "mongodb.ssl.enabled": "true",
    "mongodb.ssl.invalid.hostname.allowed": "false",
    "mongodb.ssl.truststore": "/etc/ssl/mongo/mongo-truststore.jks",
    "mongodb.ssl.truststore.password": "${TRUSTSTORE_PASSWORD}"
}
EOF

sleep 5

log "Verifying topic dbserver1ssl.inventory.customers"
# `|| true` shields against a benign post-consume `date: <epoch>: No such file or directory`
# error from playground on macOS (BSD date doesn't support GNU `-d <epoch>`); the consumed
# message is already captured in stdout by that point.
consume_output=$(playground topic consume --topic dbserver1ssl.inventory.customers --min-expected-messages 1 --timeout 60 2>&1 || true)
echo "${consume_output}"

log "Asserting record content matches what we inserted"
# Debezium serializes the MongoDB document as a JSON string inside the Avro envelope's
# `after` field, so the inner quotes are backslash-escaped in the consumer output.
expected_fields=('\"_id\": 1006' '\"first_name\": \"Bob\"' '\"last_name\": \"Hopper\"' '\"email\": \"thebob@example.com\"')
for field in "${expected_fields[@]}"; do
  if ! echo "${consume_output}" | grep -qF "${field}"; then
    logerror "❌ Expected ${field} not found in topic payload"
    exit 1
  fi
done
log "✅ Content match confirmed: _id=1006, Bob Hopper, thebob@example.com"
