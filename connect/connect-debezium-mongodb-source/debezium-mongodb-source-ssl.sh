#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ../../connect/connect-debezium-mongodb-source/ssl
cd ../../connect/connect-debezium-mongodb-source/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
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
    sudo chmod -R a+rw .
fi

# https://www.mongodb.com/community/forums/t/mongodb-4-4-2-x509/13868/5
cat mongo.key mongo.crt > mongo.pem

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
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
    sudo chmod -R a+rw .
fi

cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.ssl.yml"

# https://www.mongodb.com/docs/manual/tutorial/configure-ssl-clients/
log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
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
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.find().pretty();
EOF

log "Creating Debezium MongoDB source connector with TLS"
playground connector create-or-update --connector debezium-mongodb-source-ssl  << EOF
{
    "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
    "tasks.max" : "1",
    "mongodb.connection.string": "mongodb://mongodb:27017/?replicaSet=debezium",
    "topic.prefix": "dbserver1",
    "mongodb.user" : "debezium",
    "mongodb.password" : "dbz",
    "mongodb.ssl.enabled": "true",
    "mongodb.ssl.invalid.hostname.allowed": "false",
    "mongodb.ssl.truststore": "/tmp/truststore.jks",
    "mongodb.ssl.truststore.password": "confluent"
}
EOF

sleep 5

log "Verifying topic dbserver1.inventory.customers"
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60
