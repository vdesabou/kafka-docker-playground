#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

rm -f server.crt
rm -f server.csr
rm -f server.key
rm -f ca.crt
rm -f ca.key

#https://blog.crunchydata.com/blog/ssl-certificate-authentication-postgresql-docker-containers
log "Creating a Root Certificate Authority (CA)"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"

log "Generate the PostgreSQL server key and certificate"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=postgres"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
rm server.csr

cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ssl.yml"


log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&sslmode=verify-full&sslrootcert=/tmp/ca.crt",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

log "Show content of ORDERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log | grep "100"