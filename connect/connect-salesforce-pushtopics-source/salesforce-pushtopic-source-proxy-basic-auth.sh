#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


logerror "This example is not supposed to work since the connector does not support it"
exit 0

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.28"
then
     logwarn "minimal supported connector version is 2.0.29 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
SALESFORCE_CONSUMER_KEY=${SALESFORCE_CONSUMER_KEY:-$3}
SALESFORCE_CONSUMER_PASSWORD=${SALESFORCE_CONSUMER_PASSWORD:-$4}
SALESFORCE_SECURITY_TOKEN=${SALESFORCE_SECURITY_TOKEN:-$5}
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


if [ -z "$SALESFORCE_CONSUMER_KEY" ]
then
     logerror "SALESFORCE_CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_CONSUMER_PASSWORD" ]
then
     logerror "SALESFORCE_CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_SECURITY_TOKEN" ]
then
     logerror "SALESFORCE_SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PUSH_TOPICS_NAME=MyLeadPushTopics${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}
if [ ${#PUSH_TOPICS_NAME} -gt 25 ]; then
  PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME:0:25}
fi

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ../../connect/connect-salesforce-pushtopics-source/MyLeadPushTopics-template.apex > ../../connect/connect-salesforce-pushtopics-source/MyLeadPushTopics.apex

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.basic-auth.yml"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\""

log "Delete $PUSH_TOPICS_NAME, if required"
set +e
docker exec -i sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic WHERE Name = '$PUSH_TOPICS_NAME'];
Database.delete(pts);
EOF
set -e
log "Create $PUSH_TOPICS_NAME"
docker exec sfdx-cli sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\" -f \"/tmp/MyLeadPushTopics.apex\""

DOMAIN=$(echo $SALESFORCE_INSTANCE | cut -d "/" -f 3)
IP=$(nslookup $DOMAIN | grep Address | grep -v "#" | cut -d " " -f 2 | tail -1)
log "Blocking $DOMAIN IP $IP to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.salesforce \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "DEBUG"
}'

log "Creating Salesforce PushTopics Source connector"
playground connector create-or-update --connector salesforce-pushtopic-source-proxy-basic-auth  << EOF
{
     "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
     "kafka.topic": "sfdc-pushtopic-leads",
     "tasks.max": "1",
     "curl.logging": "true",
     "salesforce.object" : "Lead",
     "salesforce.push.topic.name" : "$PUSH_TOPICS_NAME",
     "salesforce.instance" : "$SALESFORCE_INSTANCE",
     "salesforce.username" : "$SALESFORCE_USERNAME",
     "salesforce.password" : "$SALESFORCE_PASSWORD",
     "salesforce.password.token" : "$SALESFORCE_SECURITY_TOKEN",
     "salesforce.consumer.key" : "$SALESFORCE_CONSUMER_KEY",
     "salesforce.consumer.secret" : "$SALESFORCE_CONSUMER_PASSWORD",
     "http.proxy": "squid:8888",
     "http.proxy.auth.scheme": "BASIC",
     "http.proxy.user": "admin",
     "http.proxy.password": "1234",
     "salesforce.initial.start" : "latest",
     "connection.max.message.size": "10048576",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

# [2022-01-21 13:47:19,274] DEBUG Using HTTP(S) proxy: nginx-proxy:8888 (io.confluent.salesforce.rest.SalesforceHttpClientUtil:40)
# [2022-01-21 13:47:19,292] ERROR Uncaught exception in REST call to /connectors/salesforce-pushtopic-source/config (org.apache.kafka.connect.runtime.rest.errors.ConnectExceptionMapper:61)
# org.apache.kafka.common.config.ConfigException: Unknown configuration 'http.proxy.user'
#         at org.apache.kafka.common.config.AbstractConfig.get(AbstractConfig.java:163)
#         at org.apache.kafka.common.config.AbstractConfig.getString(AbstractConfig.java:198)
#         at io.confluent.salesforce.common.SalesforceCommonConnectorConfig.httpProxyUsername(SalesforceCommonConnectorConfig.java:332)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.setHttpProxyCredentialsProvider(SalesforceHttpClientUtil.java:58)
#         at io.confluent.salesforce.rest.SalesforceHttpClientUtil.httpClientBuilder(SalesforceHttpClientUtil.java:47)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.<init>(SalesforceRestClientImpl.java:94)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.<init>(SalesforceRestClientImpl.java:83)
#         at io.confluent.salesforce.rest.SalesforceRestClientFactory.create(SalesforceRestClientFactory.java:12)
#         at io.confluent.salesforce.common.AbstractSalesforceValidation.createAndValidateClient(AbstractSalesforceValidation.java:109)
#         at io.confluent.salesforce.common.AbstractSalesforceValidation.performValidation(AbstractSalesforceValidation.java:63)
#         at io.confluent.salesforce.pushtopic.SalesforcePushTopicSourceValidation.performValidation(SalesforcePushTopicSourceValidation.java:81)
#         at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:185)
#         at io.confluent.salesforce.SalesforcePushTopicSourceConnector.validate(SalesforcePushTopicSourceConnector.java:152)
#         at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:465)
#         at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$2(AbstractHerder.java:365)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)

# [2022-01-21 13:53:53,658] INFO SalesforcePushTopicSourceConnectorConfig values: 
# 	confluent.license = 
# 	confluent.topic = _confluent-command
# 	confluent.topic.bootstrap.servers = [broker:9092]
# 	confluent.topic.replication.factor = 1
# 	connection.max.message.size = 10048576
# 	connection.timeout = 30000
# 	curl.logging = true
# 	http.proxy = nginx-proxy:8888
# 	kafka.topic = sfdc-pushtopic-leads
# 	kafka.topic.lowercase = true
# 	request.max.retries.time.ms = 900000
# 	salesforce.consumer.key = 3MVG9lsAlIP.W_V.k0nr8DU2tp2TITctLGpiBlCaIVY1jac6hN2Zp0jqlLuUQ9UopxJsW72pLdFBu40TLRd7l
# 	salesforce.consumer.secret = [hidden]
# 	salesforce.initial.start = latest
# 	salesforce.instance = xxxx
# 	salesforce.jwt.keystore.password = null
# 	salesforce.jwt.keystore.path = null
# 	salesforce.object = Lead
# 	salesforce.password = [hidden]
# 	salesforce.password.token = [hidden]
# 	salesforce.push.topic.create = true
# 	salesforce.push.topic.name = MyLeadPushTopics701
# 	salesforce.push.topic.notify.create = true
# 	salesforce.push.topic.notify.delete = true
# 	salesforce.push.topic.notify.undelete = true
# 	salesforce.push.topic.notify.update = true
# 	salesforce.username = vsaboulin@confluent.io.sumup
# 	salesforce.version = latest

sleep 5


LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx data:create:record  --target-org \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

sleep 30

log "Verify we have received the data in sfdc-pushtopic-leads topic"
playground topic consume --topic sfdc-pushtopic-leads --min-expected-messages 1 --timeout 60
