#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/mtls

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

log "Generating client (appuser or root depending on the image) key and certificates"
  if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
  then
    docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=appuser/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US"
  else
    docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/client.csr -keyout /tmp/client.key -subj "/CN=root/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US"
  fi
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -in /tmp/client.csr -days 365 -CA /tmp/rootCA.crt -CAkey /tmp/rootCA.key -CAcreateserial -out /tmp/client.crt
# need to use pk8, otherwise I got this issue https://coderanch.com/t/706596/databases/Connection-string-ssl-client-certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl pkcs8 -topk8 -outform DER -in /tmp/client.key -out /tmp/client.key.pk8 -nocrypt
rm client.csr
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-mtls.yml"

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
                    "connection.url": "jdbc:postgresql://postgres/postgres?sslmode=verify-full&sslrootcert=/tmp/root.crt&sslcert=/tmp/client.crt&sslkey=/tmp/client.key.pk8",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/postgres-source-mtls/config | jq .


sleep 5

log "Verifying topic postgres-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic postgres-customers --from-beginning --max-messages 5


