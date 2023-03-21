#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

if [ -z "$NGROK_AUTH_TOKEN" ]
then
     logerror "NGROK_AUTH_TOKEN is not set. Export it as environment variable or pass it as argument"
     logerror "Sign up at: https://dashboard.ngrok.com/signup"
     logerror "If you have already signed up, make sure your authtoken is installed."
     logerror "Your authtoken is available on your dashboard: https://dashboard.ngrok.com/get-started/your-authtoken"
     exit 1
fi

logwarn "🚨WARNING🚨"
logwarn "It is considered a security risk to run this example on your personal machine since you'll be exposing a TCP port over internet using Ngrok (https://ngrok.com)."
logwarn "It is strongly encouraged to run it on a AWS EC2 instance where you'll use Confluent Static Egress IP Addresses (https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (only available for public endpoints on AWS) to allow traffic from your Confluent Cloud cluster to your EC2 instance using EC2 Security Group."
logwarn ""
logwarn "Example in order to set EC2 Security Group with Confluent Static Egress IP Addresses and port 5432:"
logwarn "group=\$(aws ec2 describe-instances --instance-id <\$ec2-instance-id> --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[] | .GroupName')"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 5432 --cidr 13.36.88.88/32"
logwarn "aws ec2 authorize-security-group-ingress --group-name "\$group" --protocol tcp --port 5432 --cidr 13.36.88.89/32"
logwarn "etc..."

check_if_continue

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
# delete subject as required
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/asgard.public.customers-key
curl -X DELETE -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects/asgard.public.customers-value
delete_topic asgard.public.customers
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

#confluent connect plugin describe IbmMQSource

log "Create CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
create table CUSTOMERS (
        id INT PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(8),
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

insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (6, 'Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (7, 'Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (8, 'Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (9, 'Even', 'Tinham', 'etinham8@facebook.com', 'Male', 'silver', 'Virtual full-range info-mediaries');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (10, 'Brena', 'Tollerton', 'btollerton9@furl.net', 'Female', 'silver', 'Diverse tangible methodology');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (11, 'Alexandro', 'Peeke-Vout', 'apeekevouta@freewebs.com', 'Male', 'gold', 'Ameliorated value-added orchestration');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (12, 'Sheryl', 'Hackwell', 'shackwellb@paginegialle.it', 'Female', 'gold', 'Self-enabling global parallelism');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (13, 'Laney', 'Toopin', 'ltoopinc@icio.us', 'Female', 'platinum', 'Phased coherent alliance');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (14, 'Isabelita', 'Talboy', 'italboyd@imageshack.us', 'Female', 'gold', 'Cloned transitional synergy');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (15, 'Rodrique', 'Silverton', 'rsilvertone@umn.edu', 'Male', 'gold', 'Re-engineered static application');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (16, 'Clair', 'Vardy', 'cvardyf@reverbnation.com', 'Male', 'bronze', 'Expanded bottom-line Graphical User Interface');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (17, 'Brianna', 'Paradise', 'bparadiseg@nifty.com', 'Female', 'bronze', 'Open-source global toolset');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (18, 'Waldon', 'Keddey', 'wkeddeyh@weather.com', 'Male', 'gold', 'Business-focused multi-state functionalities');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (19, 'Josiah', 'Brockett', 'jbrocketti@com.com', 'Male', 'gold', 'Realigned didactic info-mediaries');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (20, 'Anselma', 'Rook', 'arookj@europa.eu', 'Female', 'gold', 'Cross-group 24/7 application');

EOF

log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

log "Adding an element to the table"
docker exec -i postgres psql -U myuser -d postgres << EOF
insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i postgres psql -U myuser -d postgres << EOF
SELECT * FROM CUSTOMERS;
EOF

cat << EOF > connector.json
{
     "connector.class": "PostgresCdcSource",
     "name": "PostgresCdcSource",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "database.hostname": "$NGROK_HOSTNAME",
     "database.port": "$NGROK_PORT",
     "database.user": "myuser",
     "database.password": "mypassword",
     "database.dbname": "postgres",
     "database.server.name": "asgard",
     "table.include.list":"public.customers",
     "plugin.name": "pgoutput",
     "output.data.format": "AVRO",
     "tasks.max": "1"
}
EOF

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

sleep 60

log "Verifying topic asgard.public.customers"
timeout 60 docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} kafka-avro-console-consumer --topic asgard.public.customers --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 5



