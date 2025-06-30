#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

DATABRICKS_HOST=${DATABRICKS_HOST:-$1}
DATABRICKS_TOKEN=${DATABRICKS_TOKEN:-$2}
DATABRICKS_HTTP_PATH=${DATABRICKS_HTTP_PATH:-$3}

cd ../../connect/connect-jdbc-databricks-source
if [ ! -f ${PWD}/DatabricksJDBC42.jar ]
then
     log "Downloading DatabricksJDBC42.jar "
     wget -q https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/jdbc/2.7.3/DatabricksJDBC42-2.7.3.1010.zip
     unzip DatabricksJDBC42-2.7.3.1010.zip -d lib
     mv lib/DatabricksJDBC-2.7.3.1010/DatabricksJDBC42.jar .
     rm -rf DatabricksJDBC42-2.7.3.1010.zip 
     rm -rf lib
fi
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


docker exec -i databricks-sql-cli-container bash -c "python databricks_sql_cli.py" <<EOF
create or replace table CUSTOMERS ( id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, first_name VARCHAR(50), last_name VARCHAR(50), email VARCHAR(50), gender VARCHAR(50), club_status VARCHAR(20), comments VARCHAR(90), create_ts timestamp DEFAULT CURRENT_TIMESTAMP , update_ts timestamp DEFAULT CURRENT_TIMESTAMP ) TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

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
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Anselma1', 'Rook1', 'arook1j@europa.eu', 'Female', 'gold', 'Cross-group 24/7 application');

select * from customers order by id;
exit
EOF

log "Creating Databricks JDBC Source connector"
playground connector create-or-update --connector jdbc-databricks-source  << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "mode": "incrementing",
               "table.whitelist": "customers",
               "incrementing.column.name": "id",
               "connection.url": "jdbc:databricks://$DATABRICKS_HOST:443/default;transportMode=http;ssl=1;AuthMech=3;httpPath=$DATABRICKS_HTTP_PATH;IgnoreTransactions=1;",
               "connection.user": "token",
               "connection.password" : "$DATABRICKS_TOKEN",
               "topic.prefix": "databricks-"
          }
EOF

sleep 5

log "Verifying topic databricks-customers"
playground topic consume --topic databricks-customers --min-expected-messages 1 --timeout 60

