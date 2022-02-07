#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"


log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "-------------------------------------"
log "Running SSL with Mutual TLS Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     --data '{
          "topics": "http-messages",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "org.apache.kafka.connect.storage.StringConverter",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
          "confluent.topic.ssl.keystore.password" : "confluent",
          "confluent.topic.ssl.key.password" : "confluent",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.sasl.mechanism": "PLAIN",
          "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
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
          "http.api.url": "https://http-service-mtls-auth:8443/api/messages",
          "auth.type": "NONE",
          "ssl.enabled": "true",
          "https.ssl.truststore.location": "/etc/kafka/secrets/kafka.connect.truststore.jks",
          "https.ssl.truststore.type": "JKS",
          "https.ssl.truststore.password": "confluent",
          "https.ssl.keystore.location": "/tmp/keystore.http-service-mtls-auth.jks",
          "https.ssl.keystore.type": "JKS",
          "https.ssl.keystore.password": "confluent",
          "https.ssl.key.password": "confluent",
          "https.ssl.protocol": "TLSv1.2"
          }' \
     https://localhost:8083/connectors/http-mtls-sink/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl --cert ./security/http-service-mtls-auth.certificate.pem --key ./security/http-service-mtls-auth.key --tlsv1.2 --cacert ./security/snakeoil-ca-1.crt  -X GET https://localhost:8643/api/messages | jq .

# [2021-04-21 14:14:37,262] ERROR WorkerSinkTask{id=http-mtls-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Error while processing HTTP request with Url : https://http-service-mtls-auth:8443/api/messages, Payload : 1, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: Path does not chain with any of the trust anchors (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : https://http-service-mtls-auth:8443/api/messages, Payload : 1, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: Path does not chain with any of the trust anchors
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:450)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:285)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:181)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:70)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:586)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: Error while processing HTTP request with Url : https://http-service-mtls-auth:8443/api/messages, Payload : 1, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: Path does not chain with any of the trust anchors
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:390)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:308)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:280)
#         ... 13 more
# [2021-04-21 14:14:37,262] ERROR WorkerSinkTask{id=http-mtls-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:614)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : https://http-service-mtls-auth:8443/api/messages, Payload : 1, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: Path does not chain with any of the trust anchors
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:450)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:285)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:181)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:70)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:586)
#         ... 10 more
# Caused by: Error while processing HTTP request with Url : https://http-service-mtls-auth:8443/api/messages, Payload : 1, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertPathValidatorException: Path does not chain with any of the trust anchors
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:390)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:308)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:280)
#         ... 13 more