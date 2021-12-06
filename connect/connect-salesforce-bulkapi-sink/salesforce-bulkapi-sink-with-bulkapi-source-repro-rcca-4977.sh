#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_repro () {
     MAX_WAIT=600
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for error invalid session ID exception to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "invalid session ID exception" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'invalid session ID exception' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

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

# second account (for Bulk API sink)
SALESFORCE_USERNAME_ACCOUNT2=${SALESFORCE_USERNAME_ACCOUNT2:-$6}
SALESFORCE_PASSWORD_ACCOUNT2=${SALESFORCE_PASSWORD_ACCOUNT2:-$7}
SECURITY_TOKEN_ACCOUNT2=${SECURITY_TOKEN_ACCOUNT2:-$8}
SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}

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

PUSH_TOPICS_NAME=MyLeadPushTopics${TAG}
PUSH_TOPICS_NAME=${PUSH_TOPICS_NAME//[-._]/}

sed -e "s|:PUSH_TOPIC_NAME:|$PUSH_TOPICS_NAME|g" \
    ${DIR}/MyLeadPushTopics-template.apex > ${DIR}/MyLeadPushTopics.apex

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-rcca-4977.yml"


log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx force:data:record:create  -u \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

log "Creating Salesforce Bulk API Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSourceConnector",
                    "kafka.topic": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-source/config | jq .



sleep 10

log "Verify we have received the data in sfdc-bulkapi-leads topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-bulkapi-leads --from-beginning --max-messages 1

log "Creating Salesforce Bulk API Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
                    "topics": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE_ACCOUNT2"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN_ACCOUNT2"'",
                    "salesforce.ignore.fields" : "CleanStatus",
                    "salesforce.ignore.reference.fields" : "true",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "transforms" : "InsertField",
                    "transforms.InsertField.type" : "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.InsertField.static.field" : "_EventType",
                    "transforms.InsertField.static.value" : "created",
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

log "Login with sfdx CLI on the account #2"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SECURITY_TOKEN_ACCOUNT2\""

log "Get the Lead created on account #2"
docker exec sfdx-cli sh -c "sfdx force:data:record:get  -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -w \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "$LEAD_FIRSTNAME" /tmp/result.log


log "Creating Salesforce Bulk API Sink connector 2"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.salesforce.SalesforceBulkApiSinkConnector",
                    "topics": "sfdc-bulkapi-leads",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.object" : "Lead",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE_ACCOUNT2"'",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME_ACCOUNT2"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD_ACCOUNT2"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN_ACCOUNT2"'",
                    "salesforce.ignore.fields" : "CleanStatus",
                    "salesforce.ignore.reference.fields" : "true",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "error-responses",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.result.topic.name": "success-responses",
                    "reporter.result.topic.replication.factor": 1,
                    "transforms" : "InsertField",
                    "transforms.InsertField.type" : "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.InsertField.static.field" : "_EventType",
                    "transforms.InsertField.static.value" : "created",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-bulkapi-sink2/config | jq .

log "Inject another Lead"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

LEAD_FIRSTNAME=John_$RANDOM
LEAD_LASTNAME=Doe_$RANDOM
log "Add a Lead to Salesforce: $LEAD_FIRSTNAME $LEAD_LASTNAME"
docker exec sfdx-cli sh -c "sfdx force:data:record:create  -u \"$SALESFORCE_USERNAME\" -s Lead -v \"FirstName='$LEAD_FIRSTNAME' LastName='$LEAD_LASTNAME' Company=Confluent\""

wait_for_repro


# javax.net.ssl|DEBUG|6A|task-thread-salesforce-bulkapi-sink-0|2021-12-04 11:04:28.802 UTC|SSLCipher.java:1671|Plaintext after DECRYPTION (
#   0000: 48 54 54 50 2F 31 2E 31   20 35 30 30 20 53 65 72  HTTP/1.1 500 Ser
#   0010: 76 65 72 20 45 72 72 6F   72 0D 0A 44 61 74 65 3A  ver Error..Date:
#   0020: 20 53 61 74 2C 20 30 34   20 44 65 63 20 32 30 32   Sat, 04 Dec 202
#   0030: 31 20 31 31 3A 30 34 3A   32 38 20 47 4D 54 0D 0A  1 11:04:28 GMT..
#   0040: 43 61 63 68 65 2D 43 6F   6E 74 72 6F 6C 3A 20 6E  Cache-Control: n
#   0050: 6F 2D 63 61 63 68 65 2C   6D 75 73 74 2D 72 65 76  o-cache,must-rev
#   0060: 61 6C 69 64 61 74 65 2C   6D 61 78 2D 61 67 65 3D  alidate,max-age=
#   0070: 30 2C 6E 6F 2D 73 74 6F   72 65 2C 70 72 69 76 61  0,no-store,priva
#   0080: 74 65 0D 0A 53 65 74 2D   43 6F 6F 6B 69 65 3A 20  te..Set-Cookie: 
#   0090: 42 72 6F 77 73 65 72 49   64 3D 38 31 63 44 52 56  BrowserId=81cDRV
#   00A0: 54 78 45 65 79 70 61 43   56 76 73 6C 71 4E 4D 67  TxEeypaCVvslqNMg
#   00B0: 3B 20 64 6F 6D 61 69 6E   3D 2E 73 61 6C 65 73 66  ; domain=.salesf
#   00C0: 6F 72 63 65 2E 63 6F 6D   3B 20 70 61 74 68 3D 2F  orce.com; path=/
#   00D0: 3B 20 65 78 70 69 72 65   73 3D 53 75 6E 2C 20 30  ; expires=Sun, 0
#   00E0: 34 2D 44 65 63 2D 32 30   32 32 20 31 31 3A 30 34  4-Dec-2022 11:04
#   00F0: 3A 32 38 20 47 4D 54 3B   20 4D 61 78 2D 41 67 65  :28 GMT; Max-Age
#   0100: 3D 33 31 35 33 36 30 30   30 0D 0A 43 6F 6E 74 65  =31536000..Conte
#   0110: 6E 74 2D 54 79 70 65 3A   20 74 65 78 74 2F 78 6D  nt-Type: text/xm
#   0120: 6C 3B 20 63 68 61 72 73   65 74 3D 75 74 66 2D 38  l; charset=utf-8
#   0130: 0D 0A 54 72 61 6E 73 66   65 72 2D 45 6E 63 6F 64  ..Transfer-Encod
#   0140: 69 6E 67 3A 20 63 68 75   6E 6B 65 64 0D 0A 0D 0A  ing: chunked....
#   0150: 34 33 43 0D 0A 3C 3F 78   6D 6C 20 76 65 72 73 69  43C..<?xml versi
#   0160: 6F 6E 3D 22 31 2E 30 22   20 65 6E 63 6F 64 69 6E  on="1.0" encodin
#   0170: 67 3D 22 55 54 46 2D 38   22 3F 3E 3C 73 6F 61 70  g="UTF-8"?><soap
#   0180: 65 6E 76 3A 45 6E 76 65   6C 6F 70 65 20 78 6D 6C  env:Envelope xml
#   0190: 6E 73 3A 73 6F 61 70 65   6E 76 3D 22 68 74 74 70  ns:soapenv="http
#   01A0: 3A 2F 2F 73 63 68 65 6D   61 73 2E 78 6D 6C 73 6F  ://schemas.xmlso
#   01B0: 61 70 2E 6F 72 67 2F 73   6F 61 70 2F 65 6E 76 65  ap.org/soap/enve
#   01C0: 6C 6F 70 65 2F 22 20 78   6D 6C 6E 73 3A 73 66 3D  lope/" xmlns:sf=
#   01D0: 22 75 72 6E 3A 66 61 75   6C 74 2E 70 61 72 74 6E  "urn:fault.partn
#   01E0: 65 72 2E 73 6F 61 70 2E   73 66 6F 72 63 65 2E 63  er.soap.sforce.c
#   01F0: 6F 6D 22 20 78 6D 6C 6E   73 3A 78 73 69 3D 22 68  om" xmlns:xsi="h
#   0200: 74 74 70 3A 2F 2F 77 77   77 2E 77 33 2E 6F 72 67  ttp://www.w3.org
#   0210: 2F 32 30 30 31 2F 58 4D   4C 53 63 68 65 6D 61 2D  /2001/XMLSchema-
#   0220: 69 6E 73 74 61 6E 63 65   22 3E 3C 73 6F 61 70 65  instance"><soape
#   0230: 6E 76 3A 42 6F 64 79 3E   3C 73 6F 61 70 65 6E 76  nv:Body><soapenv
#   0240: 3A 46 61 75 6C 74 3E 3C   66 61 75 6C 74 63 6F 64  :Fault><faultcod
#   0250: 65 3E 73 66 3A 49 4E 56   41 4C 49 44 5F 53 45 53  e>sf:INVALID_SES
#   0260: 53 49 4F 4E 5F 49 44 3C   2F 66 61 75 6C 74 63 6F  SION_ID</faultco
#   0270: 64 65 3E 3C 66 61 75 6C   74 73 74 72 69 6E 67 3E  de><faultstring>
#   0280: 49 4E 56 41 4C 49 44 5F   53 45 53 53 49 4F 4E 5F  INVALID_SESSION_
#   0290: 49 44 3A 20 49 6E 76 61   6C 69 64 20 53 65 73 73  ID: Invalid Sess
#   02A0: 69 6F 6E 20 49 44 20 66   6F 75 6E 64 20 69 6E 20  ion ID found in 
#   02B0: 53 65 73 73 69 6F 6E 48   65 61 64 65 72 3A 20 49  SessionHeader: I
#   02C0: 6C 6C 65 67 61 6C 20 53   65 73 73 69 6F 6E 2E 20  llegal Session. 
#   02D0: 53 65 73 73 69 6F 6E 20   6E 6F 74 20 66 6F 75 6E  Session not foun
#   02E0: 64 2C 20 6D 69 73 73 69   6E 67 20 73 65 73 73 69  d, missing sessi
#   02F0: 6F 6E 20 68 61 73 68 3A   20 42 53 6B 71 70 57 53  on hash: BSkqpWS
#   0300: 44 6E 57 66 38 66 2F 7A   45 73 42 50 77 56 32 4C  DnWf8f/zEsBPwV2L
#   0310: 72 6E 4B 37 2B 6E 52 31   48 68 58 73 43 4A 39 58  rnK7+nR1HhXsCJ9X
#   0320: 41 30 49 34 3D 0A 54 68   69 73 20 65 72 72 6F 72  A0I4=.This error
#   0330: 20 75 73 75 61 6C 6C 79   20 6F 63 63 75 72 73 20   usually occurs 
#   0340: 61 66 74 65 72 20 61 20   73 65 73 73 69 6F 6E 20  after a session 
#   0350: 65 78 70 69 72 65 73 20   6F 72 20 61 20 75 73 65  expires or a use
#   0360: 72 20 6C 6F 67 73 20 6F   75 74 2E 20 44 65 63 6F  r logs out. Deco
#   0370: 64 65 72 3A 20 44 61 74   61 49 6E 44 62 53 65 73  der: DataInDbSes
#   0380: 73 69 6F 6E 4B 65 79 44   65 63 6F 64 65 72 3C 2F  sionKeyDecoder</
#   0390: 66 61 75 6C 74 73 74 72   69 6E 67 3E 3C 64 65 74  faultstring><det
#   03A0: 61 69 6C 3E 3C 73 66 3A   55 6E 65 78 70 65 63 74  ail><sf:Unexpect
#   03B0: 65 64 45 72 72 6F 72 46   61 75 6C 74 20 78 73 69  edErrorFault xsi
#   03C0: 3A 74 79 70 65 3D 22 73   66 3A 55 6E 65 78 70 65  :type="sf:Unexpe
#   03D0: 63 74 65 64 45 72 72 6F   72 46 61 75 6C 74 22 3E  ctedErrorFault">
#   03E0: 3C 73 66 3A 65 78 63 65   70 74 69 6F 6E 43 6F 64  <sf:exceptionCod
#   03F0: 65 3E 49 4E 56 41 4C 49   44 5F 53 45 53 53 49 4F  e>INVALID_SESSIO
#   0400: 4E 5F 49 44 3C 2F 73 66   3A 65 78 63 65 70 74 69  N_ID</sf:excepti
#   0410: 6F 6E 43 6F 64 65 3E 3C   73 66 3A 65 78 63 65 70  onCode><sf:excep
#   0420: 74 69 6F 6E 4D 65 73 73   61 67 65 3E 49 6E 76 61  tionMessage>Inva
#   0430: 6C 69 64 20 53 65 73 73   69 6F 6E 20 49 44 20 66  lid Session ID f
#   0440: 6F 75 6E 64 20 69 6E 20   53 65 73 73 69 6F 6E 48  ound in SessionH
#   0450: 65 61 64 65 72 3A 20 49   6C 6C 65 67 61 6C 20 53  eader: Illegal S
#   0460: 65 73 73 69 6F 6E 2E 20   53 65 73 73 69 6F 6E 20  ession. Session 
#   0470: 6E 6F 74 20 66 6F 75 6E   64 2C 20 6D 69 73 73 69  not found, missi
#   0480: 6E 67 20 73 65 73 73 69   6F 6E 20 68 61 73 68 3A  ng session hash:
#   0490: 20 42 53 6B 71 70 57 53   44 6E 57 66 38 66 2F 7A   BSkqpWSDnWf8f/z
#   04A0: 45 73 42 50 77 56 32 4C   72 6E 4B 37 2B 6E 52 31  EsBPwV2LrnK7+nR1
#   04B0: 48 68 58 73 43 4A 39 58   41 30 49 34 3D 0A 54 68  HhXsCJ9XA0I4=.Th
#   04C0: 69 73 20 65 72 72 6F 72   20 75 73 75 61 6C 6C 79  is error usually
#   04D0: 20 6F 63 63 75 72 73 20   61 66 74 65 72 20 61 20   occurs after a 
#   04E0: 73 65 73 73 69 6F 6E 20   65 78 70 69 72 65 73 20  session expires 
#   04F0: 6F 72 20 61 20 75 73 65   72 20 6C 6F 67 73 20 6F  or a user logs o
#   0500: 75 74 2E 20 44 65 63 6F   64 65 72 3A 20 44 61 74  ut. Decoder: Dat
#   0510: 61 49 6E 44 62 53 65 73   73 69 6F 6E 4B 65 79 44  aInDbSessionKeyD
#   0520: 65 63 6F 64 65 72 3C 2F   73 66 3A 65 78 63 65 70  ecoder</sf:excep
#   0530: 74 69 6F 6E 4D 65 73 73   61 67 65 3E 3C 2F 73 66  tionMessage></sf
#   0540: 3A 55 6E 65 78 70 65 63   74 65 64 45 72 72 6F 72  :UnexpectedError
#   0550: 46 61 75 6C 74 3E 3C 2F   64 65 74 61 69 6C 3E 3C  Fault></detail><
#   0560: 2F 73 6F 61 70 65 6E 76   3A 46 61 75 6C 74 3E 3C  /soapenv:Fault><
#   0570: 2F 73 6F 61 70 65 6E 76   3A 42 6F 64 79 3E 3C 2F  /soapenv:Body></
#   0580: 73 6F 61 70 65 6E 76 3A   45 6E 76 65 6C 6F 70 65  soapenv:Envelope
#   0590: 3E                                                 >