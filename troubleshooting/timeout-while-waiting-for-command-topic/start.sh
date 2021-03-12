#!/bin/bash
set -e

# https://github.com/confluentinc/ksql/issues/5503
export TAG=6.0.0

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh

# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic users << EOF
# {"ROWKEY": "foo", "namesp":"n1", "email":"email@dot.org"}
# EOF

# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic pageviews << EOF
# {"userid": "foo", "namesp":"n1", "pageid":"1"}
# EOF

log "Create stream and table"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

create table users (
    rowkey varchar primary key,
    namesp varchar,
    email varchar
  ) with (
    kafka_topic='users',
    value_format='json',partitions=1
  );

  create stream pageviews (
    userid varchar,
    namesp varchar,
    pageid varchar
  ) with (
    kafka_topic='pageviews',
    value_format='json',partitions=1
  );

INSERT INTO users (rowkey,namesp,email) VALUES ('foo', 'n1', 'email');
INSERT INTO pageviews (userid,namesp,pageid) VALUES ('foo', 'n1', '1');
EOF


log "Problematic join"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

create stream joined as
  select
    p.*
  from pageviews p
    join users u on p.userid=u.rowkey
  where p.namesp='n1'
  emit changes;
EOF

docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic users --from-beginning --max-messages 1
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic pageviews --from-beginning --max-messages 1
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic JOINED --from-beginning --max-messages 1

log "Try to create another stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

create table users2 (rowkey varchar primary key, namesp varchar, email varchar) with (kafka_topic='users',value_format='json');
EOF