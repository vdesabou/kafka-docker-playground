#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ../../connect/connect-mongodb-sink/ssl
cd ../../connect/connect-mongodb-sink/ssl
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

rm -f mongo.pem
rm -f mongo.crt
rm -f mongo.key

log "Create a self-signed certificate"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mongodb' -keyout /tmp/mongo.key -out /tmp/mongo.crt -days 365

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

# https://www.mongodb.com/community/forums/t/mongodb-4-4-2-x509/13868/5
cat mongo.key mongo.crt > mongo.pem

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

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -importcert -alias mongoCACert -noprompt -file /tmp/mongo.crt -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssl.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

log "Creating MongoDB sink connector"
playground connector create-or-update --connector mongodb-sink  << EOF
{
    "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
    "tasks.max" : "1",
    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017/?tls=true",
    "database":"inventory",
    "collection":"customers",
    "topics":"orders"
}
EOF

sleep 10

log "View record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.find().pretty();
EOF

docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF > output.txt
use inventory
db.customers.find().pretty();
EOF
grep "foo" output.txt
rm output.txt