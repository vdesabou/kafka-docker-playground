#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/ssl

rm -f server.crt
rm -f server.csr
rm -f server.key
rm -f rootCA.crt
rm -f rootCA.csr
rm -f rootCA.key
rm -f rootCA.srl

# generate a key for our root CA certificate
log "Generating key for root CA certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl genrsa -des3 -passout pass:confluent -out /tmp/rootCA.pass.key 2048
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl rsa -passin pass:confluent -in /tmp/rootCA.pass.key -out /tmp/rootCA.key
rm rootCA.pass.key

# create and self sign the root CA certificate
log "Creating self-signed root CA certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -x509 -new -nodes -key /tmp/rootCA.key -sha256 -days 1024 -out  /tmp/rootCA.crt -subj "/CN=ca1.test.confluent.io/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US"
log "Self-signed root CA certificate (rootCA.crt) is:"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -in  /tmp/rootCA.crt -text -noout

# generate a key for our server certificate
log "Generating key for server certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl genrsa -des3 -passout pass:confluent -out  /tmp/server.pass.key 2048
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl rsa -passin pass:confluent -in  /tmp/server.pass.key -out  /tmp/server.key
rm server.pass.key

# create a certificate request for our server. This includes a subject alternative name so either localhost or postgres can be used to address it
log "Creating server certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -key  /tmp/server.key -out  /tmp/server.csr -subj "/CN=postgres/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US" -addext "subjectAltName=DNS:postgres,DNS:localhost"
log "Server certificate signing request (server.csr) is:"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -verify -in /tmp/server.csr -text -noout

# use our CA certificate and key to create a signed version of the server certificate
log "Signing server certificate using our root CA certificate and key"
cat << EOF > extfile
[SAN]
subjectAltName=DNS:postgres,DNS:localhost
EOF
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -sha256 -days 365 -in /tmp/server.csr -CA /tmp/rootCA.crt -CAkey /tmp/rootCA.key -CAcreateserial -out /tmp/server.crt -extensions SAN -extfile /tmp/extfile
chmod og-rwx server.key
log "Server certificate signed with our root CA certificate (server.crt) is:"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -in /tmp/server.crt -text -noout

cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-ssl.yml"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Creating JDBC PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&sslmode=verify-full&sslrootcert=/tmp/root.crt",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/postgres-source-ssl/config | jq .


sleep 5

log "Verifying topic postgres-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic postgres-customers --from-beginning --max-messages 5


