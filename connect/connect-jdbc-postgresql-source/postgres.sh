#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../connect/connect-jdbc-postgresql-source
     log "🌪️ SQL_DATAGEN is set"
     for component in postgres-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
     cd -
else
     log "🛑 SQL_DATAGEN is not set"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
create table CUSTOMERS (
        id SERIAL PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(20),
        comments VARCHAR(90),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
        update_ts timestamp DEFAULT CURRENT_TIMESTAMP
);


-- Courtesy of https://techblog.covermymeds.com/databases/on-update-timestamps-mysql-vs-postgres/
CREATE FUNCTION update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS \$\$
  BEGIN
    NEW.update_ts = NOW();
    RETURN NEW;
  END;
\$\$;

CREATE TRIGGER t1_updated_at_modtime BEFORE UPDATE ON CUSTOMERS FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Even', 'Tinham', 'etinham8@facebook.com', 'Male', 'silver', 'Virtual full-range info-mediaries');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Brena', 'Tollerton', 'btollerton9@furl.net', 'Female', 'silver', 'Diverse tangible methodology');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Alexandro', 'Peeke-Vout', 'apeekevouta@freewebs.com', 'Male', 'gold', 'Ameliorated value-added orchestration');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Sheryl', 'Hackwell', 'shackwellb@paginegialle.it', 'Female', 'gold', 'Self-enabling global parallelism');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Laney', 'Toopin', 'ltoopinc@icio.us', 'Female', 'platinum', 'Phased coherent alliance');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Isabelita', 'Talboy', 'italboyd@imageshack.us', 'Female', 'gold', 'Cloned transitional synergy');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Rodrique', 'Silverton', 'rsilvertone@umn.edu', 'Male', 'gold', 'Re-engineered static application');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Clair', 'Vardy', 'cvardyf@reverbnation.com', 'Male', 'bronze', 'Expanded bottom-line Graphical User Interface');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Brianna', 'Paradise', 'bparadiseg@nifty.com', 'Female', 'bronze', 'Open-source global toolset');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Waldon', 'Keddey', 'wkeddeyh@weather.com', 'Male', 'gold', 'Business-focused multi-state functionalities');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Josiah', 'Brockett', 'jbrocketti@com.com', 'Male', 'gold', 'Realigned didactic info-mediaries');
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Anselma', 'Rook', 'arookj@europa.eu', 'Female', 'gold', 'Cross-group 24/7 application');

EOF

log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

log "Adding an element to the table"
docker exec -i postgres psql -U myuser -d postgres << EOF
insert into customers (first_name, last_name, email, gender, comments) values ('Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

log "Creating JDBC PostgreSQL source connector"
playground connector create-or-update --connector postgres-source  << EOF
{
              "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
              "tasks.max": "1",
              "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
              "table.whitelist": "customers",
              "mode": "timestamp+incrementing",
              "timestamp.column.name": "update_ts",
              "incrementing.column.name": "id",
              "topic.prefix": "postgres-",
              "validate.non.null":"false",
              "errors.log.enable": "true",
              "errors.log.include.messages": "true"
          }
EOF


sleep 5

log "Verifying topic postgres-customers"
playground topic consume --topic postgres-customers --min-expected-messages 5 --timeout 60


if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --connectionUrl 'jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false' --maxPoolSize 10 --durationTimeMin $DURATION"
fi
