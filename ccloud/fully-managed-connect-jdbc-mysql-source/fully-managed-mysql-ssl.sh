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


set +e
playground topic delete --topic orders
set -e

playground topic create --topic orders

docker compose build
docker compose down -v --remove-orphans
docker compose up -d

sleep 15

log "Getting certs from mysql container and transform them to JKS"
mkdir -p ${PWD}/security/
rm -rf ${PWD}/security/*
# https://dev.mysql.com/doc/connector-j/5.1/en/connector-j-reference-using-ssl.html
docker cp mysql:/var/lib/mysql/ca.pem ${PWD}/security/
docker cp mysql:/var/lib/mysql/client-key.pem ${PWD}/security/
docker cp mysql:/var/lib/mysql/client-cert.pem ${PWD}/security/

log "Creating JKS from pem files"
cd ${PWD}/security/
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} keytool -importcert -alias MySQLCACert -noprompt -file /tmp/ca.pem -keystore /tmp/truststore.jks -storepass mypassword
# Convert the client key and certificate files to a PKCS #12 archive
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl pkcs12 -export -in /tmp/client-cert.pem -inkey /tmp/client-key.pem -name "mysqlclient" -passout pass:mypassword -out /tmp/client-keystore.p12
# Import the client key and certificate into a Java keystore:
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} keytool -importkeystore -srckeystore /tmp/client-keystore.p12 -srcstoretype pkcs12 -srcstorepass mypassword -destkeystore /tmp/keystore.jks -deststoretype JKS -deststorepass mypassword
cd -

log "Create table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

CREATE TABLE team (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);


INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'kafka',
  'kafka@apache.org',
  NOW()
);

ALTER TABLE team AUTO_INCREMENT = 101;
describe team;
select * from team;
EOF

log "Adding an element to the table"
docker exec -i mysql mysql --user=root --password=password --user=userssl --password=password --ssl-mode=VERIFY_CA --ssl-ca=/var/lib/mysql/ca.pem --ssl-cert=/var/lib/mysql/client-cert.pem --ssl-key=/var/lib/mysql/client-key.pem --database=mydb << EOF
USE mydb;

INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'another',
  'another@apache.org',
  NOW()
);
EOF

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="MySqlSource"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground fully-managed-connector delete --connector $connector_name
set -e

log "Creating fully managed connector"
playground fully-managed-connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MySqlSource",
  "name": "MySqlSource",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "output.data.format": "JSON",
  "connection.host": "$NGROK_HOSTNAME",
  "connection.port": "$NGROK_PORT",
  "connection.user": "userssl",
  "connection.password": "password",
  "db.name": "mydb",
  "table.whitelist": "team",
  "db.timezone": "UTC",
  "timestamp.column.name":"last_modified",
  "incrementing.column.name":"id",
  "topic.prefix":"mysql-",
  "tasks.max": "1",
  "ssl.mode": "verify-ca",
  "ssl.truststorefile": "$PWD/security/truststore.jks",
  "ssl.truststorepassword": "mypassword"
}
EOF
wait_for_ccloud_connector_up $connector_name 300


# log "Creating MySQL source connector"
# playground connector create-or-update --connector mysql-ssl-source  << EOF
# {
#   "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
#   "tasks.max":"10",
#   "connection.url": "jdbc:mysql://mysql:3306/mydb?user=userssl&password=password&verifyServerCertificate=true&useSSL=true&requireSSL=true&enabledTLSProtocols=TLSv1,TLSv1.1,TLSv1.2,TLSv1.3",
#   "table.whitelist":"team",
#   "mode":"timestamp+incrementing",
#   "timestamp.column.name":"last_modified",
#   "incrementing.column.name":"id",
#   "topic.prefix":"mysql-"
# }
# EOF

sleep 5

log "Verifying topic mysql-team"
playground topic consume --topic mysql-team --min-expected-messages 2 --timeout 60


