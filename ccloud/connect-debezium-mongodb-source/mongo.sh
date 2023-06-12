#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     playground topic create --topic dbserver1.inventory.customers
     playground topic create --topic dbserver1.config.system.sessions
     set -e
fi

log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "debezium", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh << EOF
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
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([
{ _id : 1006, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF

log "Creating Debezium MongoDB source connector"
playground connector create-or-update --connector debezium-mongodb-source << EOF
{
               "connector.class" : "io.debezium.connector.mongodb.MongoDbConnector",
               "tasks.max" : "1",
               "mongodb.hosts" : "debezium/mongodb:27017",
               "mongodb.user" : "debezium",
               "mongodb.password" : "dbz",

               "_comment": "old version before 2.x",
               "mongodb.name": "dbserver1",
               "_comment": "new version since 2.x",
               "topic.prefix": "dbserver1",

               "topic.creation.default.replication.factor": "-1",
               "topic.creation.default.partitions": "-1"
          }
EOF


sleep 5

log "Verifying topic dbserver1.inventory.customers"
playground topic consume --topic dbserver1.inventory.customers --min-expected-messages 1 --timeout 60
