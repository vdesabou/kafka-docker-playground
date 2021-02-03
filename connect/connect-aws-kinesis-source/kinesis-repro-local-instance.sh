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

# [2021-02-03 14:50:20,730] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:20,778] INFO [Worker clientId=connect-1, groupId=connect-cluster] Session key updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:34,135] DEBUG Internal logging successfully configured to commons logger: true (com.amazonaws.AmazonWebServiceClient)
# [2021-02-03 14:50:34,329] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@67ae59e8: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:34,329] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@588af4f4: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:34,332] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@76fa71da: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:34,360] DEBUG Admin mbean registered under com.amazonaws.management:type=AwsSdkMetrics (com.amazonaws.metrics.AwsSdkMetrics)
# [2021-02-03 14:50:34,403] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:34,403] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:34,405] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:34,418] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@4d586a55 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:34,422] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: d1305963-7114-77bc-dbde-c0aed8b77fff, Content-Length: 2, Content-Type: application/x-amz-cbor-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.ListStreams, )  (com.amazonaws.request)
# [2021-02-03 14:50:34,457] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:d1305963-7114-77bc-dbde-c0aed8b77fff
# amz-sdk-retry:0/0/500
# content-length:2
# content-type:application/x-amz-cbor-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210203T145034Z
# x-amz-target:Kinesis_20131202.ListStreams

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# 58daaf73604c8f2c4e3584b7bf43e64efaf6845deca4ef4f295a94633876e900" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,457] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210203T145034Z
# 20210203/eu-west-3/kinesis/aws4_request
# 4a496d633525d12904b6ea379a395b934ba8aef4735a28615844e974605856c8" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,463] DEBUG Generating a new signing key as the signing key not available in the cache for the date 1612310400000 (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,538] DEBUG connecting to kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,538] DEBUG Connecting socket to kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 with timeout 10000 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,574] DEBUG Enabled protocols: [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,574] DEBUG Enabled cipher suites:[TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, TLS_DHE_RSA_WITH_AES_256_GCM_SHA384, TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256, TLS_DHE_DSS_WITH_AES_256_GCM_SHA384, TLS_DHE_RSA_WITH_AES_128_GCM_SHA256, TLS_DHE_DSS_WITH_AES_128_GCM_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384, TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256, TLS_DHE_RSA_WITH_AES_256_CBC_SHA256, TLS_DHE_DSS_WITH_AES_256_CBC_SHA256, TLS_DHE_RSA_WITH_AES_128_CBC_SHA256, TLS_DHE_DSS_WITH_AES_128_CBC_SHA256, TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384, TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256, TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256, TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384, TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384, TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256, TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256, TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA, TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA, TLS_DHE_RSA_WITH_AES_256_CBC_SHA, TLS_DHE_DSS_WITH_AES_256_CBC_SHA, TLS_DHE_RSA_WITH_AES_128_CBC_SHA, TLS_DHE_DSS_WITH_AES_128_CBC_SHA, TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA, TLS_ECDH_RSA_WITH_AES_256_CBC_SHA, TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA, TLS_ECDH_RSA_WITH_AES_128_CBC_SHA, TLS_RSA_WITH_AES_256_GCM_SHA384, TLS_RSA_WITH_AES_128_GCM_SHA256, TLS_RSA_WITH_AES_256_CBC_SHA256, TLS_RSA_WITH_AES_128_CBC_SHA256, TLS_RSA_WITH_AES_256_CBC_SHA, TLS_RSA_WITH_AES_128_CBC_SHA, TLS_EMPTY_RENEGOTIATION_INFO_SCSV] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,574] DEBUG socket.getSupportedProtocols(): [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1, SSLv3, SSLv2Hello], socket.getEnabledProtocols(): [TLSv1.3, TLSv1.2, TLSv1.1, TLSv1] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,575] DEBUG TLS protocol enabled for SSL handshake: [TLSv1.2, TLSv1.1, TLSv1, TLSv1.3] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,575] DEBUG Starting handshake (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,719] DEBUG Secure session established (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,719] DEBUG  negotiated protocol: TLSv1.2 (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,719] DEBUG  negotiated cipher suite: TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,720] DEBUG  peer principal: CN=kinesis.eu-west-3.amazonaws.com (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,720] DEBUG  peer alternative names: [*.kinesis.eu-west-3.vpce.amazonaws.com, kinesis.eu-west-3.amazonaws.com] (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,720] DEBUG  issuer principal: CN=Amazon, OU=Server CA 1B, O=Amazon, C=US (com.amazonaws.http.conn.ssl.SdkTLSSocketFactory)
# [2021-02-03 14:50:34,723] DEBUG created: kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-03 14:50:34,759] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-03 14:50:34,763] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-03 14:50:34,764] DEBUG Received successful response: 200, AWS Request ID: e921e8cf-f04e-c458-b1b5-52b5bf06cee0 (com.amazonaws.request)
# [2021-02-03 14:50:34,764] DEBUG x-amzn-RequestId: e921e8cf-f04e-c458-b1b5-52b5bf06cee0 (com.amazonaws.requestId)
# [2021-02-03 14:50:34,764] DEBUG AWS Extended Request ID: DoDyuCNXinpQSm9vlYwSI8pByKTw2HAf/eZ9dF/lBKhehkXTAir7RMoqtYJUHnzFQdAKS1+6zk8Zqr4kelyQhGqad62NeFIV (com.amazonaws.requestId)
# [2021-02-03 14:50:34,765] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: 09097658-0abc-e1a7-3280-6830c8d9c130, Content-Length: 31, Content-Type: application/x-amz-cbor-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-03 14:50:34,766] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:09097658-0abc-e1a7-3280-6830c8d9c130
# amz-sdk-retry:0/0/500
# content-length:31
# content-type:application/x-amz-cbor-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210203T145034Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# afc276fb52b6a4241d5ea8cbea0a9cf8a8f9f9013d6815cceb741e04af59dedf" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,766] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210203T145034Z
# 20210203/eu-west-3/kinesis/aws4_request
# e227079d76be7478a870f02ad71a46e0e06040e45dcdef5a01bad567c1069155" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,795] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-03 14:50:34,799] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-03 14:50:34,799] DEBUG Received successful response: 200, AWS Request ID: e818b243-00a4-8f55-b08c-08394fec85ed (com.amazonaws.request)
# [2021-02-03 14:50:34,799] DEBUG x-amzn-RequestId: e818b243-00a4-8f55-b08c-08394fec85ed (com.amazonaws.requestId)
# [2021-02-03 14:50:34,799] DEBUG AWS Extended Request ID: ID3SSsqaKwYPDUxNgz0Trq+VWXFMBYW5x4eMWwCWoezZZHewyiAV1vOzXWC8+dTX5DISnx2h92nCUiupfX75aybY/Du/Qpfu (com.amazonaws.requestId)
# [2021-02-03 14:50:34,800] DEBUG Sending Request: POST https://kinesis.eu-west-3.amazonaws.com / Headers: (amz-sdk-invocation-id: 0c4f0a6c-e149-c8bd-3812-2a38b13f9955, Content-Length: 31, Content-Type: application/x-amz-cbor-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-03 14:50:34,800] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:0c4f0a6c-e149-c8bd-3812-2a38b13f9955
# amz-sdk-retry:0/0/500
# content-length:31
# content-type:application/x-amz-cbor-1.1
# host:kinesis.eu-west-3.amazonaws.com
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210203T145034Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# afc276fb52b6a4241d5ea8cbea0a9cf8a8f9f9013d6815cceb741e04af59dedf" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,800] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210203T145034Z
# 20210203/eu-west-3/kinesis/aws4_request
# b4c718d8a2acba41ad0fbd52a19961530077b1d563efd42a850b7834a6f5b90e" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:34,831] TRACE Parsing service response JSON (com.amazonaws.request)
# [2021-02-03 14:50:34,832] TRACE Done parsing service response (com.amazonaws.request)
# [2021-02-03 14:50:34,832] DEBUG Received successful response: 200, AWS Request ID: faee1ba9-a138-7f22-a27a-a1d3ee70759a (com.amazonaws.request)
# [2021-02-03 14:50:34,832] DEBUG x-amzn-RequestId: faee1ba9-a138-7f22-a27a-a1d3ee70759a (com.amazonaws.requestId)
# [2021-02-03 14:50:34,832] DEBUG AWS Extended Request ID: bo6RE0CrfBrLBRgaZ5ud7ZUvCWf4YCo957R5MVgcur2k6P35UYWX7lpxZugdQWe2MI1PVyT/KhmJmUIsgO5Q0DXGGNHcj8il (com.amazonaws.requestId)
# [2021-02-03 14:50:34,837] INFO AbstractConfig values:
#  (org.apache.kafka.common.config.AbstractConfig)
# [2021-02-03 14:50:34,844] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector kinesis-source-local config updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:35,347] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator)
# [2021-02-03 14:50:35,347] INFO [Worker clientId=connect-1, groupId=connect-cluster] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-03 14:50:35,350] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully joined group with generation Generation{generationId=2, memberId='connect-1-8dd73d27-960b-42ff-bb43-96b11bc7c12b', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-03 14:50:35,355] INFO [Worker clientId=connect-1, groupId=connect-cluster] Successfully synced group in generation Generation{generationId=2, memberId='connect-1-8dd73d27-960b-42ff-bb43-96b11bc7c12b', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator)
# [2021-02-03 14:50:35,356] INFO [Worker clientId=connect-1, groupId=connect-cluster] Joined group at generation 2 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-8dd73d27-960b-42ff-bb43-96b11bc7c12b', leaderUrl='http://connect:8083/', offset=2, connectorIds=[kinesis-source-local], taskIds=[], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:35,356] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connectors and tasks using config offset 2 (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:35,357] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connector kinesis-source-local (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:35,362] INFO Creating connector kinesis-source-local of type io.confluent.connect.kinesis.KinesisSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-02-03 14:50:35,363] INFO SourceConnectorConfig values:
#         config.action.reload = restart
#         connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = null
#         key.converter = null
#         name = kinesis-source-local
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = null
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig)
# [2021-02-03 14:50:35,364] INFO EnrichedConnectorConfig values:
#         config.action.reload = restart
#         connector.class = io.confluent.connect.kinesis.KinesisSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = null
#         key.converter = null
#         name = kinesis-source-local
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-02-03 14:50:35,369] INFO Instantiated connector kinesis-source-local with version 1.3.2 of type class io.confluent.connect.kinesis.KinesisSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-02-03 14:50:35,369] INFO Finished creating connector kinesis-source-local (org.apache.kafka.connect.runtime.Worker)
# [2021-02-03 14:50:35,373] INFO [Worker clientId=connect-1, groupId=connect-cluster] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-03 14:50:35,374] INFO Starting Kinesis source connector. (io.confluent.connect.kinesis.KinesisSourceConnector)
# [2021-02-03 14:50:35,375] INFO KinesisSourceConnectorConfig values:
#         aws.access.key.id =
#         aws.secret.key.id = null
#         confluent.license =
#         confluent.topic = _confluent-command
#         confluent.topic.bootstrap.servers = [broker:9092]
#         confluent.topic.replication.factor = 1
#         kafka.topic = kinesis_topic
#         kinesis.base.url = http://kinesis-local:4567
#         kinesis.credentials.provider.class = class com.amazonaws.auth.DefaultAWSCredentialsProviderChain
#         kinesis.empty.records.backoff.ms = 5000
#         kinesis.non.proxy.hosts = []
#         kinesis.position = TRIM_HORIZON
#         kinesis.proxy.password = [hidden]
#         kinesis.proxy.url =
#         kinesis.proxy.username =
#         kinesis.record.limit = 500
#         kinesis.region = eu-west-3
#         kinesis.shard.id = .*
#         kinesis.shard.timestamp =
#         kinesis.stream = my_kinesis_stream
#         kinesis.throughput.exceeded.backoff.ms = 10000
#         shard.ids = []
#  (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-03 14:50:35,375] DEBUG Using Credentials Provider Chain com.amazonaws.auth.DefaultAWSCredentialsProviderChain@265a5625 (io.confluent.connect.kinesis.KinesisSourceConnectorConfig)
# [2021-02-03 14:50:35,378] DEBUG Unable to load configuration from com.amazonaws.monitoring.EnvironmentVariableCsmConfigurationProvider@67ae59e8: Unable to load Client Side Monitoring configurations from environment variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:35,380] DEBUG Unable to load configuration from com.amazonaws.monitoring.SystemPropertyCsmConfigurationProvider@588af4f4: Unable to load Client Side Monitoring configurations from system properties variables! (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:35,380] DEBUG Unable to load configuration from com.amazonaws.monitoring.ProfileCsmConfigurationProvider@76fa71da: Unable to load config file (com.amazonaws.monitoring.CsmConfigurationProviderChain)
# [2021-02-03 14:50:35,392] DEBUG Unable to load credentials from EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:35,393] DEBUG Unable to load credentials from SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey) (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:35,393] DEBUG Unable to load credentials from WebIdentityTokenCredentialsProvider: You must specify a value for roleArn and roleSessionName (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:35,398] DEBUG Loading credentials from com.amazonaws.auth.profile.ProfileCredentialsProvider@5e05be57 (com.amazonaws.auth.AWSCredentialsProviderChain)
# [2021-02-03 14:50:35,398] DEBUG Sending Request: POST http://kinesis-local:4567 / Headers: (amz-sdk-invocation-id: 3c60fa97-cb65-5070-5227-a556b4546840, Content-Length: 31, Content-Type: application/x-amz-cbor-1.1, User-Agent: aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc., X-Amz-Target: Kinesis_20131202.DescribeStream, )  (com.amazonaws.request)
# [2021-02-03 14:50:35,399] DEBUG AWS4 Canonical Request: '"POST
# /

# amz-sdk-invocation-id:3c60fa97-cb65-5070-5227-a556b4546840
# amz-sdk-retry:0/0/500
# content-length:31
# content-type:application/x-amz-cbor-1.1
# host:kinesis-local:4567
# user-agent:aws-sdk-java/1.11.784 Linux/4.19.121-linuxkit OpenJDK_64-Bit_Server_VM/11.0.9.1+1-LTS java/11.0.9.1 scala/2.13.2 kotlin/1.4.0 vendor/Azul_Systems,_Inc.
# x-amz-date:20210203T145035Z
# x-amz-target:Kinesis_20131202.DescribeStream

# amz-sdk-invocation-id;amz-sdk-retry;content-length;content-type;host;user-agent;x-amz-date;x-amz-target
# afc276fb52b6a4241d5ea8cbea0a9cf8a8f9f9013d6815cceb741e04af59dedf" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:35,399] DEBUG AWS4 String to Sign: '"AWS4-HMAC-SHA256
# 20210203T145035Z
# 20210203/us-east-1/kinesis/aws4_request
# 630f82f3af6907d16bc96adfaf2bd158badc383cc251f20fdc7ca6ba980fe118" (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:35,399] DEBUG Generating a new signing key as the signing key not available in the cache for the date 1612310400000 (com.amazonaws.auth.AWS4Signer)
# [2021-02-03 14:50:35,404] DEBUG Unable to parse HTTP response content (com.amazonaws.protocol.json.JsonContent)
# com.fasterxml.jackson.core.JsonParseException: Invalid CBOR value token (first byte): 0x3c
#  at [Source: (byte[])"<AccessDeniedException>
#   <Message>Unable to determine service/operation name to be authorized</Message>
# </AccessDeniedException>
# "; line: -1, column: 1]
#         at com.fasterxml.jackson.core.JsonParser._constructError(JsonParser.java:1840)
#         at com.fasterxml.jackson.dataformat.cbor.CBORParser._invalidToken(CBORParser.java:3321)
#         at com.fasterxml.jackson.dataformat.cbor.CBORParser.nextToken(CBORParser.java:718)
#         at com.fasterxml.jackson.databind.ObjectMapper._readTreeAndClose(ObjectMapper.java:4247)
#         at com.fasterxml.jackson.databind.ObjectMapper.readTree(ObjectMapper.java:2734)
#         at com.amazonaws.protocol.json.JsonContent.parseJsonContent(JsonContent.java:72)
#         at com.amazonaws.protocol.json.JsonContent.<init>(JsonContent.java:64)
#         at com.amazonaws.protocol.json.JsonContent.createJsonContent(JsonContent.java:54)
#         at com.amazonaws.http.JsonErrorResponseHandler.handle(JsonErrorResponseHandler.java:89)
#         at com.amazonaws.http.JsonErrorResponseHandler.handle(JsonErrorResponseHandler.java:40)
#         at com.amazonaws.http.AwsErrorResponseHandler.handleAse(AwsErrorResponseHandler.java:53)
#         at com.amazonaws.http.AwsErrorResponseHandler.handle(AwsErrorResponseHandler.java:41)
#         at com.amazonaws.http.AwsErrorResponseHandler.handle(AwsErrorResponseHandler.java:26)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleErrorResponse(AmazonHttpClient.java:1781)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleServiceErrorResponse(AmazonHttpClient.java:1383)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeOneRequest(AmazonHttpClient.java:1359)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeHelper(AmazonHttpClient.java:1139)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.doExecute(AmazonHttpClient.java:796)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeWithTimer(AmazonHttpClient.java:764)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.execute(AmazonHttpClient.java:738)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.access$500(AmazonHttpClient.java:698)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutionBuilderImpl.execute(AmazonHttpClient.java:680)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:544)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:524)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.doInvoke(AmazonKinesisClient.java:2809)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2776)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2765)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.executeDescribeStream(AmazonKinesisClient.java:875)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.describeStream(AmazonKinesisClient.java:846)
#         at io.confluent.connect.kinesis.KinesisSourceConnector.doStart(KinesisSourceConnector.java:55)
#         at io.confluent.connect.kinesis.KinesisSourceConnector.start(KinesisSourceConnector.java:48)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:186)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:211)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:350)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:333)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# WARNING: An illegal reflective access operation has occurred
# WARNING: Illegal reflective access by com.fasterxml.jackson.databind.util.ClassUtil (file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-kinesis/lib/jackson-databind-2.10.5.1.jar) to field java.lang.Throwable.cause
# WARNING: Please consider reporting this to the maintainers of com.fasterxml.jackson.databind.util.ClassUtil
# WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
# WARNING: All illegal access operations will be denied in a future release
# [2021-02-03 14:50:35,420] DEBUG Received error response: com.amazonaws.services.kinesis.model.AmazonKinesisException: null (Service: AmazonKinesis; Status Code: 403; Error Code: null; Request ID: 2c151f90-662f-11eb-8111-953a4c057cc7) (com.amazonaws.request)
# [2021-02-03 14:50:35,421] DEBUG Reported server date (from 'Date' header): Wed, 03 Feb 2021 14:50:35 GMT (com.amazonaws.retry.ClockSkewAdjuster)
# [2021-02-03 14:50:35,433] ERROR WorkerConnector{id=kinesis-source-local} Error while starting connector (org.apache.kafka.connect.runtime.WorkerConnector)
# com.amazonaws.services.kinesis.model.AmazonKinesisException: null (Service: AmazonKinesis; Status Code: 403; Error Code: null; Request ID: 2c151f90-662f-11eb-8111-953a4c057cc7)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleErrorResponse(AmazonHttpClient.java:1799)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleServiceErrorResponse(AmazonHttpClient.java:1383)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeOneRequest(AmazonHttpClient.java:1359)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeHelper(AmazonHttpClient.java:1139)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.doExecute(AmazonHttpClient.java:796)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeWithTimer(AmazonHttpClient.java:764)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.execute(AmazonHttpClient.java:738)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.access$500(AmazonHttpClient.java:698)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutionBuilderImpl.execute(AmazonHttpClient.java:680)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:544)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:524)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.doInvoke(AmazonKinesisClient.java:2809)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2776)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2765)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.executeDescribeStream(AmazonKinesisClient.java:875)
#         at com.amazonaws.services.kinesis.AmazonKinesisClient.describeStream(AmazonKinesisClient.java:846)
#         at io.confluent.connect.kinesis.KinesisSourceConnector.doStart(KinesisSourceConnector.java:55)
#         at io.confluent.connect.kinesis.KinesisSourceConnector.start(KinesisSourceConnector.java:48)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:186)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:211)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:350)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:333)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-03 14:50:35,443] ERROR [Worker clientId=connect-1, groupId=connect-cluster] Failed to start connector 'kinesis-source-local' (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# org.apache.kafka.connect.errors.ConnectException: Failed to start connector: kinesis-source-local
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$startConnector$5(DistributedHerder.java:1304)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:336)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-03 14:52:34,348] DEBUG shutting down output of kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-03 14:52:34,350] DEBUG shutting down input of kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 (com.amazonaws.internal.SdkSSLSocket)
# [2021-02-03 14:52:34,353] DEBUG closing kinesis.eu-west-3.amazonaws.com/52.46.69.49:443 (com.amazonaws.internal.SdkSSLSocket)

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
/usr/local/bin/aws kinesis --endpoint-url http://localhost:4567/ delete-stream --stream-name my_kinesis_stream