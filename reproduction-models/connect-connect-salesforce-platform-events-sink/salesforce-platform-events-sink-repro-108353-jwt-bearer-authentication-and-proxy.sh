#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
CONSUMER_KEY=${CONSUMER_KEY:-$3}
CONSUMER_PASSWORD=${CONSUMER_PASSWORD:-$4}
SECURITY_TOKEN=${SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

if [ -z "$SALESFORCE_USERNAME" ]
then
     logerror "SALESFORCE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD" ]
then
     logerror "SALESFORCE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


if [ -z "$CONSUMER_KEY" ]
then
     logerror "CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CONSUMER_PASSWORD" ]
then
     logerror "CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SECURITY_TOKEN" ]
then
     logerror "SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


# https://medium.com/@tou_sfdx/salesforce-oauth-jwt-bearer-flow-cc70bfc626c2

# manual steps:

# 1/ generate crt
# keytool -genkey -noprompt -alias salesforce-confluent -dname "CN=ca1.test.confluent.io/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US" -keystore salesforce-confluent.keystore.jks -keyalg RSA -storepass confluent -keypass confluent -deststoretype pkcs12
# keytool -keystore salesforce-confluent.keystore.jks -alias salesforce-confluent -export -file salesforce-confluent.crt -storepass confluent -keypass confluent -trustcacerts -noprompt

# 2/ Create connected app and provide crt

# 3/ approve app by opening:
# $SALESFORCE_INSTANCE/services/oauth2/authorize?response_type=token&client_id=$CONSUMER_KEY_APP_WITH_JWT&redirect_uri=https://test.salesforce.com/services/oauth2/success

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.plaintext.repro-108353-jwt-bearer-authentication-and-proxy.yml"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

log "Send Platform Events"
docker exec sfdx-cli sh -c "sfdx force:apex:execute  -u \"$SALESFORCE_USERNAME\" -f \"/tmp/event.apex\""

log "Creating Salesforce Platform Events Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSourceConnector",
                    "kafka.topic": "sfdc-platform-events",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.platform.event.name" : "MyPlatformEvent__e",
                    "http.proxy": "nginx-proxy:8888",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY_APP_WITH_JWT"'",
                    "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
                    "salesforce.jwt.keystore.password": "confluent",
                    "salesforce.initial.start" : "all",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/salesforce-platform-events-source/config | jq .




sleep 10

log "Verify we have received the data in sfdc-platform-events topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-platform-events --from-beginning --max-messages 2 --consumer.config /etc/kafka/secrets/client_without_interceptors.config

# curl --request PUT \
#   --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
#   --url https://localhost:8083/admin/loggers/io.confluent.salesforce \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
#  "level": "TRACE"
# }'

log "Creating Salesforce Platform Events Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePlatformEventSinkConnector",
                    "topics": "sfdc-platform-events",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.platform.event.name" : "MyPlatformEvent__e",
                    "http.proxy": "nginx-proxy:8888",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY_APP_WITH_JWT"'",
                    "salesforce.jwt.keystore.path": "/tmp/salesforce-confluent.keystore.jks",
                    "salesforce.jwt.keystore.password": "confluent",
                    "salesforce.initial.start" : "all",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "reporter.ssl.endpoint.identification.algorithm" : "https",
                    "reporter.sasl.mechanism" : "PLAIN",
                    "reporter.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"client\" password=\"client-secret\";",
                    "reporter.security.protocol" : "SASL_SSL",
                    "reporter.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "reporter.ssl.keystore.password" : "confluent",
                    "reporter.ssl.key.password" : "confluent",
                    "reporter.admin.ssl.endpoint.identification.algorithm" : "https",
                    "reporter.admin.sasl.mechanism" : "PLAIN",
                    "reporter.admin.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"client\" password=\"client-secret\";",
                    "reporter.admin.security.protocol" : "SASL_SSL",
                    "reporter.admin.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "reporter.admin.ssl.keystore.password" : "confluent",
                    "reporter.admin.ssl.key.password" : "confluent",
                    "reporter.producer.ssl.endpoint.identification.algorithm" : "https",
                    "reporter.producer.sasl.mechanism" : "PLAIN",
                    "reporter.producer.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"client\" password=\"client-secret\";",
                    "reporter.producer.security.protocol" : "SASL_SSL",
                    "reporter.producer.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "reporter.producer.ssl.keystore.password" : "confluent",
                    "reporter.producer.ssl.key.password" : "confluent",
                    "transforms": "MaskField",
                    "transforms.MaskField.type": "org.apache.kafka.connect.transforms.MaskField$Value",
                    "transforms.MaskField.fields": "Message__c",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/salesforce-platform-events-sink/config | jq .


sleep 10

# it is working fine, in setup I needed to do a few things:

# [2022-06-07 12:17:35,182] ERROR Could not authenticate to Salesforce, please check the provided credentials. (io.confluent.salesforce.common.AbstractSalesforceValidation:117)
# org.apache.kafka.connect.errors.ConnectException: Exception encountered while calling salesforce
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:122)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.authenticate(SalesforceRestClientImpl.java:253)
#         at io.confluent.salesforce.common.AbstractSalesforceValidation.createAndValidateClient(AbstractSalesforceValidation.java:115)
#         at io.confluent.salesforce.common.AbstractSalesforceValidation.performValidation(AbstractSalesforceValidation.java:66)
#         at io.confluent.salesforce.platformevent.validation.AbstractPlatformEventValidation.performValidation(AbstractPlatformEventValidation.java:37)
#         at io.confluent.salesforce.platformevent.validation.SalesforcePlatformEventSinkValidation.performValidation(SalesforcePlatformEventSinkValidation.java:42)
#         at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:185)
#         at io.confluent.salesforce.SalesforcePlatformEventSinkConnector.validate(SalesforcePlatformEventSinkConnector.java:65)
#         at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:532)
#         at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$4(AbstractHerder.java:436)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# {"error":"invalid_grant","error_description":"audience is invalid"}
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.executeAndParse(SalesforceHttpClientUtil.java:98)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.postAndParse(SalesforceHttpClientUtil.java:120)
#         ... 14 more
# [2022-06-07 12:17:35,184] INFO AbstractConfig values: 
#  (org.apache.kafka.common.config.AbstractConfig:376)
# see https://confluentinc.atlassian.net/browse/CCDB-4534

# when getting "user hasn't approved this consumer"
# need to open this in browser: $SALESFORCE_INSTANCE/services/oauth2/authorize?response_type=token&client_id=$CONSUMER_KEY_APP_WITH_JWT&redirect_uri=https://test.salesforce.com/services/oauth2/success

log "Verify topic success-responses"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 2 --consumer.config /etc/kafka/secrets/client_without_interceptors.config

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1