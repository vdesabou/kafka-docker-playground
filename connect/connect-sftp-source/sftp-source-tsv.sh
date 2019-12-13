#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

mkdir -p ${DIR}/upload/input
mkdir -p ${DIR}/upload/error
mkdir -p ${DIR}/upload/finished

echo $'id\tfirst_name\tlast_name\temail\tgender\tip_address\tlast_login\taccount_balance\tcountry\tfavorite_color\n1\tPadraig\tOxshott\tpoxshott0@dion.ne.jp\tMale\t47.243.121.95\t2016-06-24T22:43:42Z\t15274.22\tJP\t#06708f\n2\tEdi\tOrrah\teorrah1@cafepress.com\tFemale\t158.229.234.101\t2017-03-01T17:52:47Z\t12947.6\tCN\t#5f2aa2' > ${DIR}/upload/input/tsv-sftp-source.tsv

echo "Creating TSV SFTP Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"IGNORE",
               "input.path": "/upload/input",
               "error.path": "/upload/error",
               "finished.path": "/upload/finished",
               "input.file.pattern": "tsv-sftp-source.tsv",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true",
               "csv.separator.char": "9"
          }' \
     http://localhost:8083/connectors/sftp-source-tsv/config | jq .

sleep 5

echo "Verifying topic sftp-testing-topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic sftp-testing-topic --from-beginning --max-messages 2