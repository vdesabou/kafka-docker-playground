#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

export ELASTIC_VERSION="7.12.0"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-104309-timestamp-and-elasticsearch.yml"


log "Describing the application table in DB 'db':"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=db -e "
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified, \
  myEpochTime \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW(), \
  '2020-01-01 10:10:10' \
); "

log "Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"10",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

sleep 5

log "Verifying topic mysql-application"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-application --from-beginning --max-messages 2

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
          "tasks.max": "1",
          "topics": "mysql-application",
          "key.ignore": "true",
          "connection.url": "http://elasticsearch:9200",
          "transforms":"Cast",
          "transforms.Cast.type":"org.apache.kafka.connect.transforms.Cast$Value",
          "transforms.Cast.spec":"myEpochTime:string"
          }' \
     http://localhost:8083/connectors/elasticsearch-sink/config | jq .

sleep 5


log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/mysql-application/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log


# {
#   "took" : 60,
#   "timed_out" : false,
#   "_shards" : {
#     "total" : 1,
#     "successful" : 1,
#     "skipped" : 0,
#     "failed" : 0
#   },
#   "hits" : {
#     "total" : {
#       "value" : 2,
#       "relation" : "eq"
#     },
#     "max_score" : 1.0,
#     "hits" : [
#       {
#         "_index" : "mysql-application",
#         "_type" : "_doc",
#         "_id" : "mysql-application+0+0",
#         "_score" : 1.0,
#         "_source" : {
#           "id" : 1,
#           "name" : "kafka",
#           "team_email" : "kafka@apache.org",
#           "last_modified" : 1652279910000,
#           "myEpochTime" : "2020-01-01"
#         }
#       },
#       {
#         "_index" : "mysql-application",
#         "_type" : "_doc",
#         "_id" : "mysql-application+0+1",
#         "_score" : 1.0,
#         "_source" : {
#           "id" : 2,
#           "name" : "another",
#           "team_email" : "another@apache.org",
#           "last_modified" : 1652279952000,
#           "myEpochTime" : "2020-01-01"
#         }
#       }
#     ]
#   }
# }