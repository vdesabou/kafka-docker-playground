#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar ]
then
     log "Build kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar"
     git clone https://github.com/matt-mangia/kafka-admin.git
     cp ${DIR}/QueryBuilder.java vertica-stream-writer/src/main/java/com/github/jcustenborder/vertica/QueryBuilder.java
     docker run -it --rm -v "${DIR}/kafka-admin":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/kafka-admin/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

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


# generate kafka-admin.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/kafka-admin-template.properties > ${DIR}/kafka-admin.properties

#log "Pull the configured topics & ACLs from a cluster and print to stdout"
#java -jar ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar -properties ${DIR}/kafka-admin.properties -dump

log "Pull the configured topics & ACLs from a cluster and write to an output file"
java -jar ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar -properties ${DIR}/kafka-admin.properties -dump -output ${DIR}/before.yml

######################
## Service Account and ACLs
######################

##################################################
# Create a Service Account and API key and secret
# - A service account represents an application, and the service account name must be globally unique
##################################################

log "Create a new service account"
SERVICE_NAME="my-java-producer-app-1234"
log "ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME"
ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME || true
SERVICE_ACCOUNT_ID=$(ccloud service-account list | grep $SERVICE_NAME | awk '{print $1;}')

CCLOUD_CLUSTER=$(ccloud prompt -f "%k")
log "Create an API key and secret for the new service account"
log "ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $CCLOUD_CLUSTER"
OUTPUT=$(ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $CCLOUD_CLUSTER)
API_KEY_SA=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
API_SECRET_SA=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')

log "Wait 90 seconds for the user and service account key and secret to propagate"
sleep 90

CLIENT_CONFIG="/tmp/client.config"
log "Create a local configuration file $CLIENT_CONFIG for the client to connect to Confluent Cloud with the newly created API key and secret"
log "Write properties to $CLIENT_CONFIG:"
cat <<EOF > $CLIENT_CONFIG
ssl.endpoint.identification.algorithm=https
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
bootstrap.servers=${BOOTSTRAP_SERVERS}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="${API_KEY_SA}" password\="${API_SECRET_SA}";
EOF

##################################################
# Run a Java client: before and after ACLs
#
# When ACLs are enabled on your Confluent Cloud cluster,
# by default no client applications are authorized.
#
# The following steps show the same Java producer failing at first due to
# 'TopicAuthorizationException' and then passing once the appropriate
# ACLs are configured
##################################################

TOPIC_ACL="kafka-admin-acl-topic"
set +e
create_topic $TOPIC_ACL

log "By default, no ACLs are configured"
log "ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID

log "Run the Java producer to $TOPIC_ACL: before ACLs"
LOG1="/tmp/log.1"
docker cp $CLIENT_CONFIG producer-acl:/tmp/
docker exec producer-acl bash -c "java -jar producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC_ACL" > $LOG1 2>&1
log "# Check logs for 'org.apache.kafka.common.errors.TopicAuthorizationException'"
OUTPUT=$(grep "org.apache.kafka.common.errors.TopicAuthorizationException" $LOG1)
if [[ ! -z $OUTPUT ]]; then
  log "PASS: Producer failed due to org.apache.kafka.common.errors.TopicAuthorizationException (expected because there are no ACLs to allow this client application)"
else
  logerror "FAIL: Something went wrong, check $LOG1"
fi

log "Create ACLs for the service account, using kafka-admin"
# log "ccloud kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL"
# ccloud kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL

# generate config.yml
sed -e "s|<PRINCIPAL>|User:$SERVICE_ACCOUNT_ID|g" \
    ${DIR}/config-template.yml > ${DIR}/config.yml

java -jar ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar -properties ${DIR}/kafka-admin.properties -config ${DIR}/config.yml -execute

log "ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID

sleep 20

log "Run the Java producer to $TOPIC_ACL: after ACLs"
LOG2="/tmp/log.2"
docker exec producer-acl bash -c "java -jar producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC_ACL" > $LOG2 2>&1
log "# Check logs for '10 messages were produced to topic'"
OUTPUT=$(grep "10 messages were produced to topic" $LOG2)
if [[ ! -z $OUTPUT ]]; then
  log "PASS: Producer works"
else
  logerror "FAIL: Something went wrong, check $LOG2"
fi
cat $LOG2

log "Pull the configured topics & ACLs from a cluster and write to an output file"
java -jar ${DIR}/kafka-admin/target/kafka-admin-1.0-SNAPSHOT-jar-with-dependencies.jar -properties ${DIR}/kafka-admin.properties -dump -output ${DIR}/after.yml

##################################################
# Cleanup
# - Delete the ACLs, API key, service account
##################################################

log "Delete ACLs"
log "ccloud kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL"
ccloud kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL

log "ccloud service-account delete $SERVICE_ACCOUNT_ID"
ccloud service-account delete $SERVICE_ACCOUNT_ID

log "ccloud api-key delete $API_KEY_SA"
ccloud api-key delete $API_KEY_SA 1>/dev/null

