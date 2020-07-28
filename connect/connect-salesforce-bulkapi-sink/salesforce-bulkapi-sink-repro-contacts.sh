#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
CONSUMER_KEY=${CONSUMER_KEY:-$3}
CONSUMER_PASSWORD=${CONSUMER_PASSWORD:-$4}
SECURITY_TOKEN=${SECURITY_TOKEN:-$5}

# second account (for Bulk API sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
SECURITY_TOKEN_ACCOUNT2=${SECURITY_TOKEN_ACCOUNT2:-$8}

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

if [ -z "$SALESFORCE_USERNAME_ACCOUNT2" ]
then
     logerror "SALESFORCE_USERNAME_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD_ACCOUNT2" ]
then
     logerror "SALESFORCE_PASSWORD_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SECURITY_TOKEN_ACCOUNT2" ]
then
     logerror "SECURITY_TOKEN_ACCOUNT2 is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# the Salesforce PushTopic source connector is used to get data into Kafka and the Salesforce Bulk API sink connector is used to export data from Kafka to Salesforce


log "Creating Salesforce PushTopics Source connector"
docker exec -e SALESFORCE_USERNAME="$SALESFORCE_USERNAME" -e SALESFORCE_PASSWORD="$SALESFORCE_PASSWORD" -e CONSUMER_KEY="$CONSUMER_KEY" -e CONSUMER_PASSWORD="$CONSUMER_PASSWORD" -e SECURITY_TOKEN="$SECURITY_TOKEN" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforcePushTopicSourceConnector",
                    "kafka.topic": "sfdc-pushtopic-contacts",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Contact",
                    "salesforce.push.topic.name" : "ContactsVincent",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "all",
                    "behavior.on.api.errors":"ignore",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-pushtopic-source/config | jq .

# FIXTHIS: with default PushTopic, it fails with:
# [2020-07-28 15:42:44,494] WARN PushTopic  was not found and will be created. (io.confluent.salesforce.pushtopic.client.SalesforcePushTopicRestClientImpl)
# [2020-07-28 15:42:44,495] INFO Setting query for  to SELECT Id,IsDeleted,MasterRecordId,AccountId,LastName,FirstName,Salutation,Name,OtherCity,OtherState,OtherPostalCode,OtherCountry,OtherLatitude,OtherLongitude,OtherGeocodeAccuracy,OtherAddress,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingLatitude,MailingLongitude,MailingGeocodeAccuracy,MailingAddress,Phone,Fax,MobilePhone,HomePhone,OtherPhone,AssistantPhone,ReportsToId,Email,Title,Department,AssistantName,LeadSource,Birthdate,OwnerId,CreatedDate,CreatedById,LastModifiedDate,LastModifiedById,SystemModstamp,LastActivityDate,LastCURequestDate,LastCUUpdateDate,LastViewedDate,LastReferencedDate,EmailBouncedReason,EmailBouncedDate,IsEmailBounced,PhotoUrl,Jigsaw,JigsawContactId,CleanStatus,IndividualId,Level__c,Languages__c FROM Contact (io.confluent.salesforce.pushtopic.client.SalesforcePushTopicRestClientImpl)
# [2020-07-28 15:42:44,495] INFO Creating PushTopic  (io.confluent.salesforce.pushtopic.client.SalesforcePushTopicRestClientImpl)
# [2020-07-28 15:42:44,557] ERROR WorkerConnector{id=salesforce-pushtopic-source} Error while starting connector (org.apache.kafka.connect.runtime.WorkerConnector)
# org.apache.kafka.connect.errors.ConnectException: Exception encountered while calling salesforce
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.postAndParse(SalesforceRestClientImpl.java:256)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.pushTopic(SalesforceRestClientImpl.java:371)
#         at io.confluent.salesforce.pushtopic.client.SalesforcePushTopicRestClientImpl.createPushTopic(SalesforcePushTopicRestClientImpl.java:58)
#         at io.confluent.salesforce.pushtopic.client.SalesforcePushTopicRestClientImpl.ensurePushTopic(SalesforcePushTopicRestClientImpl.java:88)
#         at io.confluent.salesforce.SalesforcePushTopicSourceConnector.start(SalesforcePushTopicSourceConnector.java:80)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:111)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:136)
#         at org.apache.kafka.connect.runtime.WorkerConnector.transitionTo(WorkerConnector.java:196)
#         at org.apache.kafka.connect.runtime.Worker.startConnector(Worker.java:266)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.startConnector(DistributedHerder.java:1229)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.processConnectorConfigUpdates(DistributedHerder.java:552)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.tick(DistributedHerder.java:399)
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:293)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: com.google.api.client.http.HttpResponseException: 400 Bad Request
# [{"message":"Required fields are missing: [Name]","errorCode":"REQUIRED_FIELD_MISSING","fields":["Name"]}]
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1097)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.executeAndParse(SalesforceRestClientImpl.java:233)
#         at io.confluent.salesforce.rest.SalesforceRestClientImpl.postAndParse(SalesforceRestClientImpl.java:254)
#         ... 17 more

# Need to use custom PushTopics with:
# PushTopic pushTopic = new PushTopic();
# pushTopic.Name = 'ContactsVincent';
# pushTopic.Query = 'SELECT Id,IsDeleted,MasterRecordId,AccountId,LastName,FirstName,Salutation,OtherCity,OtherState,OtherPostalCode,OtherCountry,OtherLatitude,OtherLongitude,OtherGeocodeAccuracy,OtherAddress,MailingCity,MailingState,MailingPostalCode,MailingCountry,MailingLatitude,MailingLongitude,MailingGeocodeAccuracy,MailingAddress,Phone,Fax,MobilePhone,HomePhone,OtherPhone,AssistantPhone,ReportsToId,Email,Title,Department,AssistantName,LeadSource,Birthdate,OwnerId,CreatedDate,CreatedById,LastModifiedDate,LastModifiedById,SystemModstamp,LastActivityDate,LastCURequestDate,LastCUUpdateDate,LastViewedDate,LastReferencedDate,EmailBouncedReason,EmailBouncedDate,IsEmailBounced,PhotoUrl,Jigsaw,JigsawContactId,IndividualId,Level__c,Languages__c FROM Contact';
# pushTopic.ApiVersion = 49.0;
# pushTopic.NotifyForOperationCreate = true;
# pushTopic.NotifyForOperationUpdate = true;
# pushTopic.NotifyForOperationUndelete = true;
# pushTopic.NotifyForOperationDelete = true;
# pushTopic.NotifyForFields = 'Referenced';
# insert pushTopic;



sleep 10

log "Verify we have received the data in sfdc-pushtopic-contacts topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-pushtopic-contacts --from-beginning --max-messages 1


log "Creating Salesforce Bulk API Sink connector"
docker exec -e SALESFORCE_USERNAME_ACCOUNT2="$SALESFORCE_USERNAME_ACCOUNT2" -e SALESFORCE_PASSWORD_ACCOUNT2="$SALESFORCE_PASSWORD_ACCOUNT2" -e SECURITY_TOKEN_ACCOUNT2="$SECURITY_TOKEN_ACCOUNT2" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
                    "topics": "sfdc-pushtopic-contacts",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Contact",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN_ACCOUNT2"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-sink/config | jq .



sleep 10

log "Verify topic success-responses"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 1

# log "Verify topic error-responses"
# timeout 20 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1

log "Login to your SFDC account for account #2 to check that Lead has been added"