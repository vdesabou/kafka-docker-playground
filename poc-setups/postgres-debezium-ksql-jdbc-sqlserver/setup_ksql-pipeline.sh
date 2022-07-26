#!/bin/bash
set -e

docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 <<-EOF
SET 'auto.offset.reset' = 'earliest';

CREATE OR REPLACE STREAM CUSTOMERS_RAW
WITH (
    KAFKA_TOPIC = 'asgard.public.customers-raw',
    VALUE_FORMAT = 'AVRO'
);

CREATE OR REPLACE STREAM CUSTOMERS_FLAT
AS SELECT after->id as id,
          after->first_name as first_name,
          after->last_name as last_name,
          after->email as email,
          after->gender as gender,
          after->club_status as club_status,
          after->comments as comments
   FROM CUSTOMERS_RAW EMIT CHANGES;
EOF