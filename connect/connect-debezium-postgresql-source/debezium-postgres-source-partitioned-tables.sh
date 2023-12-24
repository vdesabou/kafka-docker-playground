#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create Partitioned CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
create table CUSTOMERS (
        id INT ,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(20),
        comments VARCHAR(90),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
        update_ts timestamp DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (create_ts) ;


CREATE TABLE CUSTOMERS_y2022m02 PARTITION OF CUSTOMERS
    FOR VALUES FROM ('2022-02-01 00:00:00+00') TO ('2022-03-01 00:00:00+00');

CREATE TABLE CUSTOMERS_y2022m03 PARTITION OF CUSTOMERS
    FOR VALUES FROM ('2022-03-01 00:00:00+00') TO ('2022-04-01 00:00:00+00');

CREATE TABLE CUSTOMERS_y2022m04 PARTITION OF CUSTOMERS
    FOR VALUES FROM ('2022-04-01 00:00:00+00') TO ('2022-05-01 00:00:00+00');

CREATE TABLE CUSTOMERS_y2022m05 PARTITION OF CUSTOMERS
    FOR VALUES FROM ('2022-05-01 00:00:00+00') TO ('2022-06-01 00:00:00+00');

ALTER TABLE CUSTOMERS REPLICA IDENTITY FULL;
ALTER TABLE customers_y2022m02 REPLICA IDENTITY FULL;
ALTER TABLE customers_y2022m03 REPLICA IDENTITY FULL;
ALTER TABLE customers_y2022m04 REPLICA IDENTITY FULL;
ALTER TABLE customers_y2022m05 REPLICA IDENTITY FULL;


insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy', '2022-02-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface','2022-02-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability','2022-02-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (6, 'Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (7, 'Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (8, 'Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set','2022-04-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (9, 'Even', 'Tinham', 'etinham8@facebook.com', 'Male', 'silver', 'Virtual full-range info-mediaries','2022-04-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (10, 'Brena', 'Tollerton', 'btollerton9@furl.net', 'Female', 'silver', 'Diverse tangible methodology','2022-04-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (11, 'Alexandro', 'Peeke-Vout', 'apeekevouta@freewebs.com', 'Male', 'gold', 'Ameliorated value-added orchestration','2022-05-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (12, 'Sheryl', 'Hackwell', 'shackwellb@paginegialle.it', 'Female', 'gold', 'Self-enabling global parallelism','2022-05-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (13, 'Laney', 'Toopin', 'ltoopinc@icio.us', 'Female', 'platinum', 'Phased coherent alliance','2022-05-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (14, 'Isabelita', 'Talboy', 'italboyd@imageshack.us', 'Female', 'gold', 'Cloned transitional synergy','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (15, 'Rodrique', 'Silverton', 'rsilvertone@umn.edu', 'Male', 'gold', 'Re-engineered static application','2022-05-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (16, 'Clair', 'Vardy', 'cvardyf@reverbnation.com', 'Male', 'bronze', 'Expanded bottom-line Graphical User Interface','2022-02-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (17, 'Brianna', 'Paradise', 'bparadiseg@nifty.com', 'Female', 'bronze', 'Open-source global toolset','2022-03-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (18, 'Waldon', 'Keddey', 'wkeddeyh@weather.com', 'Male', 'gold', 'Business-focused multi-state functionalities','2022-04-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (19, 'Josiah', 'Brockett', 'jbrocketti@com.com', 'Male', 'gold', 'Realigned didactic info-mediaries','2022-04-02 00:00:00+00');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments,create_ts) values (20, 'Anselma', 'Rook', 'arookj@europa.eu', 'Female', 'gold', 'Cross-group 24/7 application','2022-04-02 00:00:00+00');
EOF

log "Create a Publication with publish_via_partition_root = true:"
docker exec -i postgres psql -U myuser -d postgres << EOF
CREATE PUBLICATION "debezium_partition" FOR ALL TABLES WITH (publish_via_partition_root = true);
EOF


log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

log "Adding an element to the table"
docker exec -i postgres psql -U myuser -d postgres << EOF
insert into customers (id, first_name, last_name, email, gender, comments,create_ts) values (21, 'Sheryl', 'Paradise', 'sparadiseg@nifty.com', 'Female', 'Business-focused multi-state functionalities','2022-04-02 00:00:00+00');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

log "Creating Debezium PostgreSQL source connector"
playground connector create-or-update --connector debezium-postgres-source  << EOF
{
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "myuser",
    "database.password": "mypassword",
    "database.dbname" : "postgres",

    "_comment": "old version before 2.x",
    "database.server.name": "asgard",
    "_comment": "new version since 2.x",
    "topic.prefix": "asgard",
    
    "table.include.list": "public.customers",
    "plugin.name": "pgoutput",
    "publication.name": "debezium_partition",
    "key.converter" : "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter" : "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "transforms": "addTopicSuffix",
    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.addTopicSuffix.regex":"(.*)",
    "transforms.addTopicSuffix.replacement": "\$1-raw",

    "_comment:": "remove _ to use ExtractNewRecordState smt",
    "_transforms": "unwrap,addTopicSuffix",
    "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF



sleep 5

log "Adding more elements to the table"
docker exec -i postgres psql -U myuser -d postgres << EOF
insert into customers (id, first_name, last_name, email, gender, comments,create_ts) values (22, 'Josiah', 'Rook', 'jrookj@europa.eu', 'Male', 'Cross-group 24/7 application','2022-03-02 00:00:00+00');
insert into customers (id, first_name, last_name, email, gender, comments,create_ts) values (23, 'Rica', 'Tollerton', 'rtollerton9@furl.net', 'Male', 'Robust bandwidth-monitored budgetary management','2022-02-02 00:00:00+00');
update customers set email = 'rtollerton9@icio.us' where id = 23;
EOF


log "Verifying topic asgard.public.customers-raw"
playground topic consume --topic asgard.public.customers-raw --min-expected-messages 24 --timeout 60


