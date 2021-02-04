#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# This is required even though we use a local instance !
if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-local-instance.yml"

log "Create a Kinesis stream my_kinesis_stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ create-stream --stream-name my_kinesis_stream --shard-count 1

log "Sleep 10 seconds to let the Kinesis stream being fully started"
sleep 10

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1


log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.base.url": "http://kinesis-local:4567",
               "kinesis.stream": "my_kinesis_stream",
               "kinesis.region": "eu-west-3",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source-local/config | jq .


# FIXTHIS: getting

# [2021-02-04 10:46:56,643] INFO Finished reading KafkaBasedLog for topic connect-configs (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:46:56,643] INFO Started KafkaBasedLog for topic connect-configs (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:46:56,643] INFO Started KafkaConfigBackingStore (org.apache.kafka.connect.storage.KafkaConfigBackingStore)
# [2021-02-04 10:46:56,644] INFO [Worker clientId=connect-1, groupId=connect-cluster] Herder started (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:46:56,678] INFO [Worker clientId=connect-1, groupId=connect-cluster] Cluster ID: _RpPi--8TWOWi0Eskl6DJA (org.apache.kafka.clients.Metadata)
# [2021-02-04 10:46:56,679] INFO [Worker clientId=connect-1, groupId=connect-cluster] Discovered group coordinator broker:9092 (id: 2147483646 rack: null) (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:46:56,682] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator)
# [2021-02-04 10:46:56,682] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:46:56,690] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance failed. (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# org.apache.kafka.common.errors.MemberIdRequiredException: The group member needs to have a valid member id before actually entering a consumer group.
# [2021-02-04 10:46:56,692] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:46:56,767] INFO HV000001: Hibernate Validator 6.0.17.Final (org.hibernate.validator.internal.util.Version)
# [2021-02-04 10:46:56,943] INFO Started o.e.j.s.ServletContextHandler@3b0ed98a{/,null,AVAILABLE} (org.eclipse.jetty.server.handler.ContextHandler)
# [2021-02-04 10:46:56,943] INFO REST resources initialized; server is started and ready to handle requests (org.apache.kafka.connect.runtime.rest.RestServer)
# [2021-02-04 10:46:56,943] INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect)
# [2021-02-04 10:46:59,696] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=1, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:46:59,713] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=1, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:46:59,714] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 1 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', leaderUrl='http://connect:8083/', offset=-1, connectorIds=[], taskIds=[], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:46:59,714] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset -1 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:46:59,714] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:46:59,762] INFO [Worker clientId=connect-1, groupId=connect-cluster] Session key updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:21,400] DEBUG Internal logging successfully configured to commons logger: true (com.amazonaws.AmazonWebServiceClient)
# [2021-02-04 10:47:21,614] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@14c5e7e1: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:21,614] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@75d03756: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:21,616] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@7889e27a: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:21,633] DEBUG Admin mbean registered under com.amazonaws.management:type=AwsSdkMetrics (com.amazonaws.metrics.AwsSdkMetrics)
# [2021-02-04 10:47:21,659] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:21,659] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:21,660] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:21,668] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@44ab0521 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:21,671] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: 55e9303f-772c-1a40-37aa-10114ad43af1, Content-Length: 2, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.ListStreams, )  (com.amazonaws.request)
# [2021-02-04 10:47:21,697] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:55e9303f-772c-1a40-37aa-10114ad43af1
# amz-sdk-retry:0/0/500
# content-length:2
# content-type:application/x-amz-json-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104721Z
# x-amz-target:Kinesis_20131202.ListStreams

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:21,697] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104721Z
# 20210204/eu-west-3/kinesis/aws4_request
# 0e03fc22a52e9c7f2d8d3a11bcdb4fe262205a88d413d1ec977dd0112831be37" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:21,703] DEBUG Generating a new signing key as the signing key not available in the cache for the date 1612396800000 (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:21,777] DEBUG connecting to kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,778] DEBUG Connecting socket to kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 with timeout 10000 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,816] DEBUG Enabled protocols: [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,817] DEBUG Enabled cipher suites:[TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, TLS_DHE_RSA_WITH_AES_256_GCM_SHA384, TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256, TLS_DHE_DSS_WITH_AES_256_GCM_SHA384, TLS_DHE_RSA_WITH_AES_128_GCM_SHA256, TLS_DHE_DSS_WITH_AES_128_GCM_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384, TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256, TLS_DHE_RSA_WITH_AES_256_CBC_SHA256, TLS_DHE_DSS_WITH_AES_256_CBC_SHA256, TLS_DHE_RSA_WITH_AES_128_CBC_SHA256, TLS_DHE_DSS_WITH_AES_128_CBC_SHA256, TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384, TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256, TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256, TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384, TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384, TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256, TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA, TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA, TLS_DHE_RSA_WITH_AES_256_CBC_SHA, TLS_DHE_DSS_WITH_AES_256_CBC_SHA, TLS_DHE_RSA_WITH_AES_128_CBC_SHA, TLS_DHE_DSS_WITH_AES_128_CBC_SHA, TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA, TLS_ECDH_RSA_WITH_AES_256_CBC_SHA, TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA, TLS_ECDH_RSA_WITH_AES_128_CBC_SHA, TLS_RSA_WITH_AES_256_GCM_SHA384, TLS_RSA_WITH_AES_128_GCM_SHA256, TLS_RSA_WITH_AES_256_CBC_SHA256, TLS_RSA_WITH_AES_128_CBC_SHA256, TLS_RSA_WITH_AES_256_CBC_SHA, TLS_RSA_WITH_AES_128_CBC_SHA, TLS_EMPTY_RENEGOTIATION_INFO_SCSV] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,817] DEBUG socket.getSupportedProtocols(): [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1, SSLv3, SSLv2Hello], socket.getEnabledProtocols(): [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,817] DEBUG TLS protocol enabled for SSL handshake: [TLSv1.2, TLSv1.1, TLSv1, TLSv1.3] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,817] DEBUG Starting handshake (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG Secure session established (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG  negotiated protocol: TLSv1.2 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG  negotiated cipher suite: TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG  peer principal: CN=kinesis.eu-west-3.amazonaws.com (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG  peer alternative names: [*.kinesis.eu-west-3.vpce.amazonaws.com, kinesis.eu-west-3.amazonaws.com] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,968] DEBUG  issuer principal: CN=Amazon, OU=Server CA 1B, O=Amazon, C=US (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-04 10:47:21,972] DEBUG created: kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-04 10:47:22,008] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,010] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,010] DEBUG Received successful response: 200, AWS Request ID: cb6dcf3e-3456-cf6a-93f8-1dc4b8e7483c (com.amazonaws.request)
# [2021-02-04 10:47:22,010] DEBUG x-amzn-RequestId: cb6dcf3e-3456-cf6a-93f8-1dc4b8e7483c (com.amazonaws.requestId)
# [2021-02-04 10:47:22,010] DEBUG AWS Extended Request ID: BppD22sL8KXzkpCtihorbASaZ0zR9P4FJYLnz+XiRChh0IU/ftJoxb2BJ9gZb6fvwRFiWhdwP/oUv/6oKVpvb/ieqnMQqHw/ (com.amazonaws.requestId)
# [2021-02-04 10:47:22,012] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: 9f39ec73-8c53-e444-bada-2c9dcb8e20dc, Content-Length: 34, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-04 10:47:22,013] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:9f39ec73-8c53-e444-bada-2c9dcb8e20dc
# amz-sdk-retry:0/0/500
# content-length:34
# content-type:application/x-amz-json-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104722Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 81b5214669812bb349c0947e0cab90d0aff81ba36f0b4beec12ed84597386dab" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,013] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104722Z
# 20210204/eu-west-3/kinesis/aws4_request
# a5a241dd697eaac0b54c210e73cf59ad127d1a35dd333953f74f40de7fb5a672" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,042] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,047] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,047] DEBUG Received successful response: 200, AWS Request ID: de457506-cdae-3268-86d0-a7fc411fb53e (com.amazonaws.request)
# [2021-02-04 10:47:22,048] DEBUG x-amzn-RequestId: de457506-cdae-3268-86d0-a7fc411fb53e (com.amazonaws.requestId)
# [2021-02-04 10:47:22,048] DEBUG AWS Extended Request ID: 49rET1qsNGxiYnQtKq/WdhiAKd4Y65kUjtkD2UUgcZktBkUgPJHU+N0uI3xs7Y61H3jIm7eI0PRI4CwZz0Bx6Gp0R3O0VIlS (com.amazonaws.requestId)
# [2021-02-04 10:47:22,048] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: d439ae63-15b3-5447-23d4-b615b8be13b1, Content-Length: 34, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-04 10:47:22,049] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:d439ae63-15b3-5447-23d4-b615b8be13b1
# amz-sdk-retry:0/0/500
# content-length:34
# content-type:application/x-amz-json-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104722Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 81b5214669812bb349c0947e0cab90d0aff81ba36f0b4beec12ed84597386dab" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,049] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104722Z
# 20210204/eu-west-3/kinesis/aws4_request
# 391225a9c3b630e4b7e7f24505b26b9176c73c1e88d85a085d55c7c39af9a6f5" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,073] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,074] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,074] DEBUG Received successful response: 200, AWS Request ID: d1b722a2-7441-8ae4-8922-f058f8f00db2 (com.amazonaws.request)
# [2021-02-04 10:47:22,074] DEBUG x-amzn-RequestId: d1b722a2-7441-8ae4-8922-f058f8f00db2 (com.amazonaws.requestId)
# [2021-02-04 10:47:22,074] DEBUG AWS Extended Request ID: L7rIdIvPxSxhGBIik37r4aYKCPrqtdD/thPyx9jI+0wN0tNbILAOt6i64dVZuCpu8vN5fCtMbNxDgGFUHmuFMXZ//Kj0n3Ca (com.amazonaws.requestId)
# [2021-02-04 10:47:22,079] INFO AbstractConfig values:
#  (org.apache.kafka.common.config.AbstractConfig)
# [2021-02-04 10:47:22,087] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector kinesis-source-local config updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:22,088] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator)
# [2021-02-04 10:47:22,088] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:22,091] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=2, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:22,096] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=2, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:22,099] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 2 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', leaderUrl='http://connect:8083/', offset=2, connectorIds=[kinesis-source-local], taskIds=[], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:22,099] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 2 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:22,100] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connector kinesis-source-local (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:22,105] INFO Creating connector kinesis-source-local of type io.confluent.connect.kinesis.KinesisSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:22,106] INFO SourceConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig)
# [2021-02-04 10:47:22,107] INFO EnrichedConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-02-04 10:47:22,112] INFO Instantiated connector kinesis-source-local with version 1.3.2 of type class io.confluent.connect.kinesis.KinesisSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:22,112] INFO Finished creating connector kinesis-source-local (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:22,114] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:22,114] INFO Starting Kinesis source connector. (io.confluent.connect.kinesis.KinesisSourceConnector)
# [2021-02-04 10:47:22,115] INFO KinesisSourceConnectorConfig values:
# 	aws.access.key.id =
# 	aws.secret.key.id = null
# 	confluent.license =
# 	confluent.topic = _confluent-command
# 	confluent.topic.bootstrap.servers = [broker:9092]
# 	confluent.topic.replication.factor = 1
# 	kafka.topic = kinesis_topic
# 	kinesis.base.url = http://kinesis-local:4567
# 	kinesis.credentials.provider.class = class com.amazonaws.auth.DefaultAWSCredentialsProviderChain
# 	kinesis.empty.records.backoff.ms = 5000
# 	kinesis.non.proxy.hosts = []
# 	kinesis.position = TRIM_HORIZON
# 	kinesis.proxy.password = [hidden]
# 	kinesis.proxy.url =
# 	kinesis.proxy.username =
# 	kinesis.record.limit = 500
# 	kinesis.region = eu-west-3
# 	kinesis.shard.id = .*
# 	kinesis.shard.timestamp =
# 	kinesis.stream = my_kinesis_stream
# 	kinesis.throughput.exceeded.backoff.ms = 10000
# 	shard.ids = []
#  (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-04 10:47:22,116] DEBUG Using Credentials Provider Chain com.amazonaws.auth.DefaultAWSCredentialsProviderChain@6701fed4 (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-04 10:47:22,118] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@14c5e7e1: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,121] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@75d03756: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,121] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@7889e27a: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,133] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,134] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,134] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,139] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@aba708 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,139] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 509a8511-af10-f955-c6ca-459ad1dc73bc, Content-Length: 34, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-04 10:47:22,140] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:509a8511-af10-f955-c6ca-459ad1dc73bc
# amz-sdk-retry:0/0/500
# content-length:34
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104722Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 81b5214669812bb349c0947e0cab90d0aff81ba36f0b4beec12ed84597386dab" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,140] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104722Z
# 20210204/us-east-1/kinesis/aws4_request
# 85fae8a63fb4cd5d9f1395cd459071e02edf2f719aacee57442330260e6d53f1" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,140] DEBUG Generating a new signing key as the signing key not available in the cache for the date 1612396800000 (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,146] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,149] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,149] DEBUG Received successful response: 200, AWS Request ID: 5c3c9200-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.request)
# [2021-02-04 10:47:22,149] DEBUG x-amzn-RequestId: 5c3c9200-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.requestId)
# [2021-02-04 10:47:22,150] DEBUG AWS Extended Request ID: 8Drzph343zgBubXuIWKtgpy8KaIEDoD+Y5rx/6osK6lm1r0xLMd/la5lYBrQ1AEzcFwmaKThlY17P+jxtvhquKddtdgd26Tv (com.amazonaws.requestId)
# [2021-02-04 10:47:22,176] INFO Starting License Store (io.confluent.license.LicenseStore)
# [2021-02-04 10:47:22,176] INFO Starting KafkaBasedLog with topic _confluent-command (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:47:22,176] INFO AdminClientConfig values:
# 	bootstrap.servers = [broker:9092]
# 	client.dns.lookup = use_all_dns_ips
# 	client.id = kinesis-source-local-license-manager
# 	connections.max.idle.ms = 300000
# 	default.api.timeout.ms = 60000
# 	metadata.max.age.ms = 300000
# 	metric.reporters = []
# 	metrics.num.samples = 2
# 	metrics.recording.level = INFO
# 	metrics.sample.window.ms = 30000
# 	receive.buffer.bytes = 65536
# 	reconnect.backoff.max.ms = 1000
# 	reconnect.backoff.ms = 50
# 	request.timeout.ms = 30000
# 	retries = 2147483647
# 	retry.backoff.ms = 100
# 	sasl.client.callback.handler.class = null
# 	sasl.jaas.config = null
# 	sasl.kerberos.kinit.cmd = /usr/bin/kinit
# 	sasl.kerberos.min.time.before.relogin = 60000
# 	sasl.kerberos.service.name = null
# 	sasl.kerberos.ticket.renew.jitter = 0.05
# 	sasl.kerberos.ticket.renew.window.factor = 0.8
# 	sasl.login.callback.handler.class = null
# 	sasl.login.class = null
# 	sasl.login.refresh.buffer.seconds = 300
# 	sasl.login.refresh.min.period.seconds = 60
# 	sasl.login.refresh.window.factor = 0.8
# 	sasl.login.refresh.window.jitter = 0.05
# 	sasl.mechanism = GSSAPI
# 	security.protocol = PLAINTEXT
# 	security.providers = null
# 	send.buffer.bytes = 131072
# 	ssl.cipher.suites = null
# 	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	ssl.endpoint.identification.algorithm = https
# 	ssl.engine.factory.class = null
# 	ssl.key.password = null
# 	ssl.keymanager.algorithm = SunX509
# 	ssl.keystore.location = null
# 	ssl.keystore.password = null
# 	ssl.keystore.type = JKS
# 	ssl.protocol = TLSv1.3
# 	ssl.provider = null
# 	ssl.secure.random.implementation = null
# 	ssl.trustmanager.algorithm = PKIX
# 	ssl.truststore.location = null
# 	ssl.truststore.password = null
# 	ssl.truststore.type = JKS
#  (org.apache.kafka.clients.admin.AdminClientConfig)
# [2021-02-04 10:47:22,180] WARN The configuration 'replication.factor' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
# [2021-02-04 10:47:22,180] INFO Kafka version: 6.0.1-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,180] INFO Kafka commitId: f75f566c7a4b38d8 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,180] INFO Kafka startTimeMs: 1612435642180 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,207] INFO ProducerConfig values:
# 	acks = -1
# 	batch.size = 16384
# 	bootstrap.servers = [broker:9092]
# 	buffer.memory = 33554432
# 	client.dns.lookup = use_all_dns_ips
# 	client.id = kinesis-source-local-license-manager
# 	compression.type = none
# 	connections.max.idle.ms = 540000
# 	delivery.timeout.ms = 120000
# 	enable.idempotence = false
# 	interceptor.classes = []
# 	internal.auto.downgrade.txn.commit = false
# 	key.serializer = class io.confluent.license.LicenseStore$LicenseKeySerde
# 	linger.ms = 0
# 	max.block.ms = 60000
# 	max.in.flight.requests.per.connection = 1
# 	max.request.size = 1048576
# 	metadata.max.age.ms = 300000
# 	metadata.max.idle.ms = 300000
# 	metric.reporters = []
# 	metrics.num.samples = 2
# 	metrics.recording.level = INFO
# 	metrics.sample.window.ms = 30000
# 	partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
# 	receive.buffer.bytes = 32768
# 	reconnect.backoff.max.ms = 1000
# 	reconnect.backoff.ms = 50
# 	request.timeout.ms = 30000
# 	retries = 2147483647
# 	retry.backoff.ms = 100
# 	sasl.client.callback.handler.class = null
# 	sasl.jaas.config = null
# 	sasl.kerberos.kinit.cmd = /usr/bin/kinit
# 	sasl.kerberos.min.time.before.relogin = 60000
# 	sasl.kerberos.service.name = null
# 	sasl.kerberos.ticket.renew.jitter = 0.05
# 	sasl.kerberos.ticket.renew.window.factor = 0.8
# 	sasl.login.callback.handler.class = null
# 	sasl.login.class = null
# 	sasl.login.refresh.buffer.seconds = 300
# 	sasl.login.refresh.min.period.seconds = 60
# 	sasl.login.refresh.window.factor = 0.8
# 	sasl.login.refresh.window.jitter = 0.05
# 	sasl.mechanism = GSSAPI
# 	security.protocol = PLAINTEXT
# 	security.providers = null
# 	send.buffer.bytes = 131072
# 	ssl.cipher.suites = null
# 	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	ssl.endpoint.identification.algorithm = https
# 	ssl.engine.factory.class = null
# 	ssl.key.password = null
# 	ssl.keymanager.algorithm = SunX509
# 	ssl.keystore.location = null
# 	ssl.keystore.password = null
# 	ssl.keystore.type = JKS
# 	ssl.protocol = TLSv1.3
# 	ssl.provider = null
# 	ssl.secure.random.implementation = null
# 	ssl.trustmanager.algorithm = PKIX
# 	ssl.truststore.location = null
# 	ssl.truststore.password = null
# 	ssl.truststore.type = JKS
# 	transaction.timeout.ms = 60000
# 	transactional.id = null
# 	value.serializer = class io.confluent.license.LicenseStore$LicenseMessageSerde
#  (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:22,212] INFO Kafka version: 6.0.1-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,212] INFO Kafka commitId: f75f566c7a4b38d8 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,212] INFO Kafka startTimeMs: 1612435642212 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,214] INFO ConsumerConfig values:
# 	allow.auto.create.topics = true
# 	auto.commit.interval.ms = 5000
# 	auto.offset.reset = earliest
# 	bootstrap.servers = [broker:9092]
# 	check.crcs = true
# 	client.dns.lookup = use_all_dns_ips
# 	client.id = kinesis-source-local-license-manager
# 	client.rack =
# 	connections.max.idle.ms = 540000
# 	default.api.timeout.ms = 60000
# 	enable.auto.commit = false
# 	exclude.internal.topics = true
# 	fetch.max.bytes = 52428800
# 	fetch.max.wait.ms = 500
# 	fetch.min.bytes = 1
# 	group.id = null
# 	group.instance.id = null
# 	heartbeat.interval.ms = 3000
# 	interceptor.classes = []
# 	internal.leave.group.on.close = true
# 	internal.throw.on.fetch.stable.offset.unsupported = false
# 	isolation.level = read_uncommitted
# 	key.deserializer = class io.confluent.license.LicenseStore$LicenseKeySerde
# 	max.partition.fetch.bytes = 1048576
# 	max.poll.interval.ms = 300000
# 	max.poll.records = 500
# 	metadata.max.age.ms = 300000
# 	metric.reporters = []
# 	metrics.num.samples = 2
# 	metrics.recording.level = INFO
# 	metrics.sample.window.ms = 30000
# 	partition.assignment.strategy = [class org.apache.kafka.clients.consumer.RangeAssignor]
# 	receive.buffer.bytes = 65536
# 	reconnect.backoff.max.ms = 1000
# 	reconnect.backoff.ms = 50
# 	request.timeout.ms = 30000
# 	retry.backoff.ms = 100
# 	sasl.client.callback.handler.class = null
# 	sasl.jaas.config = null
# 	sasl.kerberos.kinit.cmd = /usr/bin/kinit
# 	sasl.kerberos.min.time.before.relogin = 60000
# 	sasl.kerberos.service.name = null
# 	sasl.kerberos.ticket.renew.jitter = 0.05
# 	sasl.kerberos.ticket.renew.window.factor = 0.8
# 	sasl.login.callback.handler.class = null
# 	sasl.login.class = null
# 	sasl.login.refresh.buffer.seconds = 300
# 	sasl.login.refresh.min.period.seconds = 60
# 	sasl.login.refresh.window.factor = 0.8
# 	sasl.login.refresh.window.jitter = 0.05
# 	sasl.mechanism = GSSAPI
# 	security.protocol = PLAINTEXT
# 	security.providers = null
# 	send.buffer.bytes = 131072
# 	session.timeout.ms = 10000
# 	ssl.cipher.suites = null
# 	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	ssl.endpoint.identification.algorithm = https
# 	ssl.engine.factory.class = null
# 	ssl.key.password = null
# 	ssl.keymanager.algorithm = SunX509
# 	ssl.keystore.location = null
# 	ssl.keystore.password = null
# 	ssl.keystore.type = JKS
# 	ssl.protocol = TLSv1.3
# 	ssl.provider = null
# 	ssl.secure.random.implementation = null
# 	ssl.trustmanager.algorithm = PKIX
# 	ssl.truststore.location = null
# 	ssl.truststore.password = null
# 	ssl.truststore.type = JKS
# 	value.deserializer = class io.confluent.license.LicenseStore$LicenseMessageSerde
#  (org.apache.kafka.clients.consumer.ConsumerConfig)
# [2021-02-04 10:47:22,218] INFO Kafka version: 6.0.1-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,218] INFO Kafka commitId: f75f566c7a4b38d8 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,218] INFO Kafka startTimeMs: 1612435642218 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,231] INFO [Producer clientId=kinesis-source-local-license-manager] Cluster ID: _RpPi--8TWOWi0Eskl6DJA (org.apache.kafka.clients.Metadata)
# [2021-02-04 10:47:22,236] INFO [Consumer clientId=kinesis-source-local-license-manager, groupId=null] Cluster ID: _RpPi--8TWOWi0Eskl6DJA (org.apache.kafka.clients.Metadata)
# [2021-02-04 10:47:22,237] INFO [Consumer clientId=kinesis-source-local-license-manager, groupId=null] Subscribed to partition(s): _confluent-command-0 (org.apache.kafka.clients.consumer.KafkaConsumer)
# [2021-02-04 10:47:22,237] INFO [Consumer clientId=kinesis-source-local-license-manager, groupId=null] Seeking to EARLIEST offset of partition _confluent-command-0 (org.apache.kafka.clients.consumer.internals.SubscriptionState)
# [2021-02-04 10:47:22,246] INFO [Consumer clientId=kinesis-source-local-license-manager, groupId=null] Resetting offset for partition _confluent-command-0 to offset 0. (org.apache.kafka.clients.consumer.internals.SubscriptionState)
# [2021-02-04 10:47:22,293] INFO Finished reading KafkaBasedLog for topic _confluent-command (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:47:22,293] INFO Started KafkaBasedLog for topic _confluent-command (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:47:22,293] INFO Started License Store (io.confluent.license.LicenseStore)
# [2021-02-04 10:47:22,296] INFO Validating Confluent License (io.confluent.connect.utils.licensing.ConnectLicenseManager)
# [2021-02-04 10:47:22,795] INFO AdminClientConfig values:
# 	bootstrap.servers = [broker:9092]
# 	client.dns.lookup = use_all_dns_ips
# 	client.id = kinesis-source-local-license-manager
# 	connections.max.idle.ms = 300000
# 	default.api.timeout.ms = 60000
# 	metadata.max.age.ms = 300000
# 	metric.reporters = []
# 	metrics.num.samples = 2
# 	metrics.recording.level = INFO
# 	metrics.sample.window.ms = 30000
# 	receive.buffer.bytes = 65536
# 	reconnect.backoff.max.ms = 1000
# 	reconnect.backoff.ms = 50
# 	request.timeout.ms = 30000
# 	retries = 2147483647
# 	retry.backoff.ms = 100
# 	sasl.client.callback.handler.class = null
# 	sasl.jaas.config = null
# 	sasl.kerberos.kinit.cmd = /usr/bin/kinit
# 	sasl.kerberos.min.time.before.relogin = 60000
# 	sasl.kerberos.service.name = null
# 	sasl.kerberos.ticket.renew.jitter = 0.05
# 	sasl.kerberos.ticket.renew.window.factor = 0.8
# 	sasl.login.callback.handler.class = null
# 	sasl.login.class = null
# 	sasl.login.refresh.buffer.seconds = 300
# 	sasl.login.refresh.min.period.seconds = 60
# 	sasl.login.refresh.window.factor = 0.8
# 	sasl.login.refresh.window.jitter = 0.05
# 	sasl.mechanism = GSSAPI
# 	security.protocol = PLAINTEXT
# 	security.providers = null
# 	send.buffer.bytes = 131072
# 	ssl.cipher.suites = null
# 	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	ssl.endpoint.identification.algorithm = https
# 	ssl.engine.factory.class = null
# 	ssl.key.password = null
# 	ssl.keymanager.algorithm = SunX509
# 	ssl.keystore.location = null
# 	ssl.keystore.password = null
# 	ssl.keystore.type = JKS
# 	ssl.protocol = TLSv1.3
# 	ssl.provider = null
# 	ssl.secure.random.implementation = null
# 	ssl.trustmanager.algorithm = PKIX
# 	ssl.truststore.location = null
# 	ssl.truststore.password = null
# 	ssl.truststore.type = JKS
#  (org.apache.kafka.clients.admin.AdminClientConfig)
# [2021-02-04 10:47:22,797] WARN The configuration 'replication.factor' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
# [2021-02-04 10:47:22,797] INFO Kafka version: 6.0.1-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,797] INFO Kafka commitId: f75f566c7a4b38d8 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,797] INFO Kafka startTimeMs: 1612435642797 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:22,849] INFO License for single cluster, single node (io.confluent.license.LicenseManager)
# [2021-02-04 10:47:22,850] INFO Closing License Store (io.confluent.license.LicenseStore)
# [2021-02-04 10:47:22,850] INFO Stopping KafkaBasedLog for topic _confluent-command (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:47:22,850] INFO [Producer clientId=kinesis-source-local-license-manager] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer)
# [2021-02-04 10:47:22,853] INFO Stopped KafkaBasedLog for topic _confluent-command (org.apache.kafka.connect.util.KafkaBasedLog)
# [2021-02-04 10:47:22,853] INFO Closed License Store (io.confluent.license.LicenseStore)
# [2021-02-04 10:47:22,854] DEBUG Using Credentials Provider Chain com.amazonaws.auth.DefaultAWSCredentialsProviderChain@2b5215f3 (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-04 10:47:22,855] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@14c5e7e1: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,855] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@75d03756: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,855] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@7889e27a: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:22,858] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,858] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,858] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,866] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@15c22905 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:22,866] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: eede3dc4-88b5-faea-c55a-b21e6fdec9b8, Content-Length: 34, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-04 10:47:22,867] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:eede3dc4-88b5-faea-c55a-b21e6fdec9b8
# amz-sdk-retry:0/0/500
# content-length:34
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104722Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 81b5214669812bb349c0947e0cab90d0aff81ba36f0b4beec12ed84597386dab" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,867] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104722Z
# 20210204/us-east-1/kinesis/aws4_request
# b8675f611331d03b1f87776a1f531396342d085b9a1d35256644e6e5903cce46" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,869] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,870] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,870] DEBUG Received successful response: 200, AWS Request ID: 5caae430-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.request)
# [2021-02-04 10:47:22,870] DEBUG x-amzn-RequestId: 5caae430-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.requestId)
# [2021-02-04 10:47:22,870] DEBUG AWS Extended Request ID: rlx7gdeObtxdbKKsJ96qJ+Rt2neda0GUZVC+4Y4dIK6jKztwAZ6e6ApEkjjYSNPE6ifzgr9C2ioHr/Ns3TVPRWHZHeeTN8bu (com.amazonaws.requestId)
# [2021-02-04 10:47:22,870] INFO Starting thread to monitor shards. (io.confluent.connect.kinesis.ShardMonitorThread)
# [2021-02-04 10:47:22,872] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 65e0c82d-41eb-8e69-d2a7-c006fa61d922, Content-Length: 34, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-04 10:47:22,873] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:65e0c82d-41eb-8e69-d2a7-c006fa61d922
# amz-sdk-retry:0/0/500
# content-length:34
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104722Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 81b5214669812bb349c0947e0cab90d0aff81ba36f0b4beec12ed84597386dab" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,873] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104722Z
# 20210204/us-east-1/kinesis/aws4_request
# 43cfba7a4cfdc68aae175a67a437cb78fe664099ea9babdd84780ffefb2cec65" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:22,876] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:22,876] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:22,877] DEBUG Received successful response: 200, AWS Request ID: 5cabf5a0-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.request)
# [2021-02-04 10:47:22,877] DEBUG x-amzn-RequestId: 5cabf5a0-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.requestId)
# [2021-02-04 10:47:22,877] DEBUG AWS Extended Request ID: YrBEARJSO3JgOLnNJ+BbiYr+cc2X9hvdV6GKqlmYCFB7zHF30CfTaeTRXDZHZRGqnwFelned2EAbTwCoH+qUKUt1QLFdxp+x (com.amazonaws.requestId)
# [2021-02-04 10:47:22,878] DEBUG Waiting 300000 ms to monitor stream and check shards. (io.confluent.connect.kinesis.ShardMonitorThread)
# [2021-02-04 10:47:22,885] INFO SourceConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig)
# [2021-02-04 10:47:22,886] INFO EnrichedConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-02-04 10:47:23,599] INFO [Worker clientId=connect-1, groupId=connect-cluster] Tasks [kinesis-source-local-0] configs updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,103] INFO [Worker clientId=connect-1, groupId=connect-cluster] Handling task config update by restarting tasks [] (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,103] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator)
# [2021-02-04 10:47:24,103] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:24,105] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=3, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:24,108] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=3, memberId='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-04 10:47:24,109] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 3 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-7eaee407-aaf1-46b4-bb27-383145815e0f', leaderUrl='http://connect:8083/', offset=4, connectorIds=[kinesis-source-local], taskIds=[kinesis-source-local-0], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,110] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 4 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,111] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting task kinesis-source-local-0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,111] INFO Creating task kinesis-source-local-0 (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,113] INFO ConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig)
# [2021-02-04 10:47:24,113] INFO EnrichedConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-02-04 10:47:24,114] INFO TaskConfig values:
# 	task.class = class io.confluent.connect.kinesis.KinesisSourceTask
#  (org.apache.kafka.connect.runtime.TaskConfig)
# [2021-02-04 10:47:24,115] INFO Instantiated task kinesis-source-local-0 with version 1.3.2 of type io.confluent.connect.kinesis.KinesisSourceTask (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,116] INFO StringConverterConfig values:
# 	converter.encoding = UTF8
# 	converter.type = key
#  (org.apache.kafka.connect.storage.StringConverterConfig)
# [2021-02-04 10:47:24,117] INFO Set up the key converter class org.apache.kafka.connect.storage.StringConverter for task kinesis-source-local-0 using the worker config (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,120] INFO AvroConverterConfig values:
# 	auto.register.schemas = true
# 	basic.auth.credentials.source = URL
# 	basic.auth.user.info = [hidden]
# 	bearer.auth.credentials.source = STATIC_TOKEN
# 	bearer.auth.token = [hidden]
# 	key.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
# 	max.schemas.per.subject = 1000
# 	proxy.host =
# 	proxy.port = -1
# 	schema.reflection = false
# 	schema.registry.basic.auth.user.info = [hidden]
# 	schema.registry.ssl.cipher.suites = null
# 	schema.registry.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	schema.registry.ssl.endpoint.identification.algorithm = https
# 	schema.registry.ssl.engine.factory.class = null
# 	schema.registry.ssl.key.password = null
# 	schema.registry.ssl.keymanager.algorithm = SunX509
# 	schema.registry.ssl.keystore.location = null
# 	schema.registry.ssl.keystore.password = null
# 	schema.registry.ssl.keystore.type = JKS
# 	schema.registry.ssl.protocol = TLSv1.3
# 	schema.registry.ssl.provider = null
# 	schema.registry.ssl.secure.random.implementation = null
# 	schema.registry.ssl.trustmanager.algorithm = PKIX
# 	schema.registry.ssl.truststore.location = null
# 	schema.registry.ssl.truststore.password = null
# 	schema.registry.ssl.truststore.type = JKS
# 	schema.registry.url = [http://schema-registry:8081]
# 	use.latest.version = false
# 	value.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
#  (io.confluent.connect.avro.AvroConverterConfig)
# [2021-02-04 10:47:24,137] INFO KafkaAvroSerializerConfig values:
# 	auto.register.schemas = true
# 	basic.auth.credentials.source = URL
# 	basic.auth.user.info = [hidden]
# 	bearer.auth.credentials.source = STATIC_TOKEN
# 	bearer.auth.token = [hidden]
# 	key.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
# 	max.schemas.per.subject = 1000
# 	proxy.host =
# 	proxy.port = -1
# 	schema.reflection = false
# 	schema.registry.basic.auth.user.info = [hidden]
# 	schema.registry.ssl.cipher.suites = null
# 	schema.registry.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	schema.registry.ssl.endpoint.identification.algorithm = https
# 	schema.registry.ssl.engine.factory.class = null
# 	schema.registry.ssl.key.password = null
# 	schema.registry.ssl.keymanager.algorithm = SunX509
# 	schema.registry.ssl.keystore.location = null
# 	schema.registry.ssl.keystore.password = null
# 	schema.registry.ssl.keystore.type = JKS
# 	schema.registry.ssl.protocol = TLSv1.3
# 	schema.registry.ssl.provider = null
# 	schema.registry.ssl.secure.random.implementation = null
# 	schema.registry.ssl.trustmanager.algorithm = PKIX
# 	schema.registry.ssl.truststore.location = null
# 	schema.registry.ssl.truststore.password = null
# 	schema.registry.ssl.truststore.type = JKS
# 	schema.registry.url = [http://schema-registry:8081]
# 	use.latest.version = false
# 	value.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
#  (io.confluent.kafka.serializers.KafkaAvroSerializerConfig)
# [2021-02-04 10:47:24,139] INFO KafkaAvroDeserializerConfig values:
# 	auto.register.schemas = true
# 	basic.auth.credentials.source = URL
# 	basic.auth.user.info = [hidden]
# 	bearer.auth.credentials.source = STATIC_TOKEN
# 	bearer.auth.token = [hidden]
# 	key.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
# 	max.schemas.per.subject = 1000
# 	proxy.host =
# 	proxy.port = -1
# 	schema.reflection = false
# 	schema.registry.basic.auth.user.info = [hidden]
# 	schema.registry.ssl.cipher.suites = null
# 	schema.registry.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	schema.registry.ssl.endpoint.identification.algorithm = https
# 	schema.registry.ssl.engine.factory.class = null
# 	schema.registry.ssl.key.password = null
# 	schema.registry.ssl.keymanager.algorithm = SunX509
# 	schema.registry.ssl.keystore.location = null
# 	schema.registry.ssl.keystore.password = null
# 	schema.registry.ssl.keystore.type = JKS
# 	schema.registry.ssl.protocol = TLSv1.3
# 	schema.registry.ssl.provider = null
# 	schema.registry.ssl.secure.random.implementation = null
# 	schema.registry.ssl.trustmanager.algorithm = PKIX
# 	schema.registry.ssl.truststore.location = null
# 	schema.registry.ssl.truststore.password = null
# 	schema.registry.ssl.truststore.type = JKS
# 	schema.registry.url = [http://schema-registry:8081]
# 	specific.avro.reader = false
# 	use.latest.version = false
# 	value.subject.name.strategy = class io.confluent.kafka.serializers.subject.TopicNameStrategy
#  (io.confluent.kafka.serializers.KafkaAvroDeserializerConfig)
# [2021-02-04 10:47:24,165] INFO AvroDataConfig values:
# 	connect.meta.data = true
# 	enhanced.avro.schema.support = false
# 	schemas.cache.config = 1000
#  (io.confluent.connect.avro.AvroDataConfig)
# [2021-02-04 10:47:24,165] INFO Set up the value converter class io.confluent.connect.avro.AvroConverter for task kinesis-source-local-0 using the worker config (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,165] INFO Set up the header converter class org.apache.kafka.connect.storage.SimpleHeaderConverter for task kinesis-source-local-0 using the worker config (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,168] INFO SourceConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig)
# [2021-02-04 10:47:24,169] INFO EnrichedConnectorConfig values:
# 	config.action.reload = restart
# 	connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
# 	errors.log.enable = false
# 	errors.log.include.messages = false
# 	errors.retry.delay.max.ms = 60000
# 	errors.retry.timeout = 0
# 	errors.tolerance = none
# 	header.converter = null
# 	key.converter = null
# 	name = kinesis-source-local
# 	predicates = []
# 	tasks.max = 1
# 	topic.creation.groups = []
# 	transforms = []
# 	value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-02-04 10:47:24,170] INFO Initializing: org.apache.kafka.connect.runtime.TransformationChain{} (org.apache.kafka.connect.runtime.Worker)
# [2021-02-04 10:47:24,171] INFO ProducerConfig values:
# 	acks = -1
# 	batch.size = 16384
# 	bootstrap.servers = [broker:9092]
# 	buffer.memory = 33554432
# 	client.dns.lookup = use_all_dns_ips
# 	client.id = connect-worker-producer
# 	compression.type = none
# 	connections.max.idle.ms = 540000
# 	delivery.timeout.ms = 2147483647
# 	enable.idempotence = false
# 	interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor]
# 	internal.auto.downgrade.txn.commit = false
# 	key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
# 	linger.ms = 0
# 	max.block.ms = 9223372036854775807
# 	max.in.flight.requests.per.connection = 1
# 	max.request.size = 1048576
# 	metadata.max.age.ms = 300000
# 	metadata.max.idle.ms = 300000
# 	metric.reporters = []
# 	metrics.num.samples = 2
# 	metrics.recording.level = INFO
# 	metrics.sample.window.ms = 30000
# 	partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
# 	receive.buffer.bytes = 32768
# 	reconnect.backoff.max.ms = 1000
# 	reconnect.backoff.ms = 50
# 	request.timeout.ms = 2147483647
# 	retries = 2147483647
# 	retry.backoff.ms = 100
# 	sasl.client.callback.handler.class = null
# 	sasl.jaas.config = null
# 	sasl.kerberos.kinit.cmd = /usr/bin/kinit
# 	sasl.kerberos.min.time.before.relogin = 60000
# 	sasl.kerberos.service.name = null
# 	sasl.kerberos.ticket.renew.jitter = 0.05
# 	sasl.kerberos.ticket.renew.window.factor = 0.8
# 	sasl.login.callback.handler.class = null
# 	sasl.login.class = null
# 	sasl.login.refresh.buffer.seconds = 300
# 	sasl.login.refresh.min.period.seconds = 60
# 	sasl.login.refresh.window.factor = 0.8
# 	sasl.login.refresh.window.jitter = 0.05
# 	sasl.mechanism = GSSAPI
# 	security.protocol = PLAINTEXT
# 	security.providers = null
# 	send.buffer.bytes = 131072
# 	ssl.cipher.suites = null
# 	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
# 	ssl.endpoint.identification.algorithm = https
# 	ssl.engine.factory.class = null
# 	ssl.key.password = null
# 	ssl.keymanager.algorithm = SunX509
# 	ssl.keystore.location = null
# 	ssl.keystore.password = null
# 	ssl.keystore.type = JKS
# 	ssl.protocol = TLSv1.3
# 	ssl.provider = null
# 	ssl.secure.random.implementation = null
# 	ssl.trustmanager.algorithm = PKIX
# 	ssl.truststore.location = null
# 	ssl.truststore.password = null
# 	ssl.truststore.type = JKS
# 	transaction.timeout.ms = 60000
# 	transactional.id = null
# 	value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#  (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.resource.connector' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.resource.version' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.connect.group.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.resource.type' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.resource.commit.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.resource.task' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'metrics.context.connect.kafka.cluster.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,174] WARN The configuration 'confluent.monitoring.interceptor.bootstrap.servers' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
# [2021-02-04 10:47:24,175] INFO Kafka version: 6.0.1-ce (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:24,175] INFO Kafka commitId: f75f566c7a4b38d8 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:24,175] INFO Kafka startTimeMs: 1612435644174 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-02-04 10:47:24,178] INFO [Producer clientId=connect-worker-producer] Cluster ID: _RpPi--8TWOWi0Eskl6DJA (org.apache.kafka.clients.Metadata)
# [2021-02-04 10:47:24,187] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-04 10:47:24,190] INFO KinesisSourceConnectorConfig values:
# 	aws.access.key.id =
# 	aws.secret.key.id = null
# 	confluent.license =
# 	confluent.topic = _confluent-command
# 	confluent.topic.bootstrap.servers = [broker:9092]
# 	confluent.topic.replication.factor = 1
# 	kafka.topic = kinesis_topic
# 	kinesis.base.url = http://kinesis-local:4567
# 	kinesis.credentials.provider.class = class com.amazonaws.auth.DefaultAWSCredentialsProviderChain
# 	kinesis.empty.records.backoff.ms = 5000
# 	kinesis.non.proxy.hosts = []
# 	kinesis.position = TRIM_HORIZON
# 	kinesis.proxy.password = [hidden]
# 	kinesis.proxy.url =
# 	kinesis.proxy.username =
# 	kinesis.record.limit = 500
# 	kinesis.region = eu-west-3
# 	kinesis.shard.id = .*
# 	kinesis.shard.timestamp =
# 	kinesis.stream = my_kinesis_stream
# 	kinesis.throughput.exceeded.backoff.ms = 10000
# 	shard.ids = [shardId-000000000000]
#  (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-04 10:47:24,190] DEBUG Using Credentials Provider Chain com.amazonaws.auth.DefaultAWSCredentialsProviderChain@5eb19764 (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-04 10:47:24,192] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@14c5e7e1: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:24,192] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@75d03756: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:24,193] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@7889e27a: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-04 10:47:24,197] TRACE Task has the following assigned shards: [shardId-000000000000] (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:24,197] TRACE Iterating over Shard ID: shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:24,214] TRACE Constructed a source partition: {kinesis.stream.name=my_kinesis_stream, kinesis.shard.id=shardId-000000000000} (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:24,568] TRACE Last offset for this partition is null (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:24,569] TRACE There is no last offset for this partition, using the old source partition scheme (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:24,570] TRACE Constructed a source partition using old source partition scheme: {kinesis.shard.id=shardId-000000000000} (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,061] TRACE Last offset for this partition, using old scheme: null (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,061] TRACE Getting a starting iterator for the shard ID shardId-000000000000 of the stream my_kinesis_stream and offset null (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,062] INFO Setting shard iterator type to TRIM_HORIZON for shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,065] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:25,065] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:25,065] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:25,069] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@5bf70c96 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-04 10:47:25,069] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 174be55b-d792-344b-1b21-37c9af8f8e94, Content-Length: 102, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.GetShardIterator, )  (com.amazonaws.request)
# [2021-02-04 10:47:25,070] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:174be55b-d792-344b-1b21-37c9af8f8e94
# amz-sdk-retry:0/0/500
# content-length:102
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104725Z
# x-amz-target:Kinesis_20131202.GetShardIterator

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 4c81a23bb5cd2f4e42a9ca1ffa06397e7d16642c791f7286c00486792cbcb640" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:25,070] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104725Z
# 20210204/us-east-1/kinesis/aws4_request
# fca5b7edef786d277b0dcad188e8cc0ac082cba122707a8a0060c831b37d4d8c" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:25,075] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:25,076] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:25,076] DEBUG Received successful response: 200, AWS Request ID: 5dfb0ae0-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.request)
# [2021-02-04 10:47:25,076] DEBUG x-amzn-RequestId: 5dfb0ae0-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.requestId)
# [2021-02-04 10:47:25,076] DEBUG AWS Extended Request ID: ZmMVwg1OLOKJV06/Hoi5FHTYePjg/cXoV95hmIgxnCDPrczoMgMh58XBo7NhymJsktGNiT16GTKjW5o6piFjNv723W/nAelG (com.amazonaws.requestId)
# [2021-02-04 10:47:25,076] INFO Using shard iterator AAAAAAAAAAGnoxaAij5fV0zIsoZ2+TEc0m7nwJGRN/jsAQ0xNqZUjvmAZsus89dh0MB+fSyORZQN2DepTCwNpEX3ZwZ7voDn+EHNV04JvMOPB7LO8wtA9e6dt7AgivZEIzuOUkXJx1MbHCYVdITKIipHab6zN7sP25YV5oCzuUdPH9L/BO9DA/770hJu8vCPPRG1PE8hI54JL/4VvHDEQAcUsc2v9XFe for shard shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,076] INFO WorkerSourceTask{id=kinesis-source-local-0} Source task finished initialization and start (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-04 10:47:25,076] TRACE Polling Kinesis using the following requests: {shardId-000000000000={ShardIterator: AAAAAAAAAAGnoxaAij5fV0zIsoZ2+TEc0m7nwJGRN/jsAQ0xNqZUjvmAZsus89dh0MB+fSyORZQN2DepTCwNpEX3ZwZ7voDn+EHNV04JvMOPB7LO8wtA9e6dt7AgivZEIzuOUkXJx1MbHCYVdITKIipHab6zN7sP25YV5oCzuUdPH9L/BO9DA/770hJu8vCPPRG1PE8hI54JL/4VvHDEQAcUsc2v9XFe,Limit: 500}} (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,077] TRACE Getting records for the following request: {ShardIterator: AAAAAAAAAAGnoxaAij5fV0zIsoZ2+TEc0m7nwJGRN/jsAQ0xNqZUjvmAZsus89dh0MB+fSyORZQN2DepTCwNpEX3ZwZ7voDn+EHNV04JvMOPB7LO8wtA9e6dt7AgivZEIzuOUkXJx1MbHCYVdITKIipHab6zN7sP25YV5oCzuUdPH9L/BO9DA/770hJu8vCPPRG1PE8hI54JL/4VvHDEQAcUsc2v9XFe,Limit: 500}(1 out of 1), shard ID: shardId-000000000000 (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,079] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 20fc3a31-5567-04c6-21ba-367a6a7b03e7, Content-Length: 256, Content-Type: application/x-amz-json-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.GetRecords, )  (com.amazonaws.request)
# [2021-02-04 10:47:25,079] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:20fc3a31-5567-04c6-21ba-367a6a7b03e7
# amz-sdk-retry:0/0/500
# content-length:256
# content-type:application/x-amz-json-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210204T104725Z
# x-amz-target:Kinesis_20131202.GetRecords

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# b41426a77f4b7f186cc7ceadbd46c92026cbbea342d7f4ae23f1ba7e5831cb34" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:25,080] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210204T104725Z
# 20210204/us-east-1/kinesis/aws4_request
# 26bb6871e22868294164f551f905ec5af032001fdaf46865ce6dbdab640a13a0" (com.amazonaws.auth.AWS4Signer)
# [2021-02-04 10:47:25,084] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-04 10:47:25,095] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-04 10:47:25,095] DEBUG Received successful response: 200, AWS Request ID: 5dfc9180-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.request)
# [2021-02-04 10:47:25,095] DEBUG x-amzn-RequestId: 5dfc9180-66d6-11eb-a113-8fdddc19aec1 (com.amazonaws.requestId)
# [2021-02-04 10:47:25,095] DEBUG AWS Extended Request ID: 7/n2XvsoMwj4xmMIJ2zl0qqBx6WaGGzz9IqMYTPkMf6yMlAZ1qtaavMXr3txxExauhTg98UHQr9+yC2v2dQexwA9CCfxMUn1 (com.amazonaws.requestId)
# [2021-02-04 10:47:25,095] TRACE 0 record(s) returned from shard shardId-000000000000. (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,096] TRACE Adding record {SequenceNumber: 49615193565133414827506360529248115362734450286411120642,Data: java.nio.HeapByteBuffer[pos=0 lim=9 cap=9],PartitionKey: 123,} to the result (io.confluent.connect.kinesis.KinesisSourceTask)
# [2021-02-04 10:47:25,098] INFO WorkerSourceTask{id=kinesis-source-local-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-04 10:47:25,098] INFO WorkerSourceTask{id=kinesis-source-local-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-02-04 10:47:25,098] ERROR WorkerSourceTask{id=kinesis-source-local-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# java.lang.NullPointerException
# 	at io.confluent.connect.kinesis.RecordConverter.sourceRecord(RecordConverter.java:63)
# 	at io.confluent.connect.kinesis.KinesisSourceTask.poll(KinesisSourceTask.java:143)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:289)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:256)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-04 10:47:25,098] ERROR WorkerSourceTask{id=kinesis-source-local-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# [2021-02-04 10:47:25,098] INFO [Producer clientId=connect-worker-producer] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer)
# [2021-02-04 10:47:36,733] DEBUG shutting down output of kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-04 10:47:36,735] DEBUG shutting down input of kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-04 10:47:36,737] DEBUG closing kinesis.eu-west-3.amazonaws.com/52.46.65.93:443 (com.amazonaws.internal.SdkSSLSocket)


log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ delete-stream --stream-name my_kinesis_stream