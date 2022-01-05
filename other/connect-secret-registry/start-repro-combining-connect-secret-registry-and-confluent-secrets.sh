#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.99"; then
    logwarn "WARN: Confluent Secrets is available since CP 5.3 only"
    exit 111
fi

rm -f ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/secret.txt
rm -f ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/CONFLUENT_SECURITY_MASTER_KEY
docker run -i --rm -v ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets:/secrets cnfldemos/tools:0.3 bash -c '
echo "Generate master key"
confluent-v1 secret master-key generate --local-secrets-file /secrets/secret.txt --passphrase @/secrets/passphrase.txt > /tmp/result.log 2>&1
cat /tmp/result.log
export CONFLUENT_SECURITY_MASTER_KEY=$(grep "Master Key" /tmp/result.log | cut -d"|" -f 3 | sed "s/ //g" | tail -1 | tr -d "\n")
echo "$CONFLUENT_SECURITY_MASTER_KEY" > /secrets/CONFLUENT_SECURITY_MASTER_KEY
echo "Encrypting my-secret-property in file my-config-file.properties"
confluent-v1 secret file encrypt --local-secrets-file /secrets/secret.txt --remote-secrets-file /etc/kafka/secrets/secret.txt --config my-secret-property --config-file /secrets/my-config-file.properties
'

export CONFLUENT_SECURITY_MASTER_KEY=$(cat ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/CONFLUENT_SECURITY_MASTER_KEY | sed 's/ //g' | tail -1 | tr -d '\n')
log "Exporting CONFLUENT_SECURITY_MASTER_KEY=$CONFLUENT_SECURITY_MASTER_KEY"

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.repro-combining-connect-secret-registry-and-confluent-secrets.yml"

log "Sending messages to topic rbac_topic"
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_sasl_plain.config

log "Checking messages from topic rbac_topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic  --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_sasl_plain.config --consumer-property group.id=clientAvro --from-beginning --max-messages 1

log "Registering secret username with superUser"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/username/versions | jq .

log "Registering secret password with superUser"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/password/versions | jq .

log "Creating FileStream Sink connector"
curl -X PUT \
     -u connectorSubmitter:connectorSubmitter \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "rbac_topic",
               "file": "/tmp/output.json",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter.basic.auth.user.info": "connectorSA:connectorSA",
               "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"${secret:my-rbac-connector:username}\" password=\"${secret:my-rbac-connector:password}\" metadataServerUrls=\"http://broker:8091\";"
          }' \
     http://localhost:8083/connectors/my-rbac-connector/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.


# ===> User
# uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)
# ===> Configuring ...
# ===> Running preflight checks ... 
# ===> Check if Kafka is healthy ...
# SLF4J: Class path contains multiple SLF4J bindings.
# SLF4J: Found binding in [jar:file:/usr/share/java/kafka/slf4j-log4j12-1.7.30.jar!/org/slf4j/impl/StaticLoggerBinder.class]
# SLF4J: Found binding in [jar:file:/usr/share/java/cp-base-new/slf4j-log4j12-1.7.30.jar!/org/slf4j/impl/StaticLoggerBinder.class]
# SLF4J: Found binding in [jar:file:/usr/share/java/cp-base-new/slf4j-simple-1.7.30.jar!/org/slf4j/impl/StaticLoggerBinder.class]
# SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
# SLF4J: Actual binding is of type [org.slf4j.impl.Log4jLoggerFactory]
# [2022-01-05 16:23:59,973] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:23:59,973] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:23:59,982] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:23:59,985] ERROR Failed to authenticate (org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule:318)
# java.io.IOException: Failed to authenticate
# 	at io.confluent.kafka.clients.plugins.auth.token.AbstractTokenLoginCallbackHandler.handle(AbstractTokenLoginCallbackHandler.java:102)
# 	at org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule.identifyToken(OAuthBearerLoginModule.java:316)
# 	at org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule.login(OAuthBearerLoginModule.java:301)
# 	at java.base/javax.security.auth.login.LoginContext.invoke(LoginContext.java:726)
# 	at java.base/javax.security.auth.login.LoginContext$4.run(LoginContext.java:665)
# 	at java.base/javax.security.auth.login.LoginContext$4.run(LoginContext.java:663)
# 	at java.base/java.security.AccessController.doPrivileged(Native Method)
# 	at java.base/javax.security.auth.login.LoginContext.invokePriv(LoginContext.java:663)
# 	at java.base/javax.security.auth.login.LoginContext.login(LoginContext.java:574)
# 	at org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.login(ExpiringCredentialRefreshingLogin.java:204)
# 	at org.apache.kafka.common.security.oauthbearer.internals.OAuthBearerRefreshingLogin.login(OAuthBearerRefreshingLogin.java:150)
# 	at org.apache.kafka.common.security.authenticator.LoginManager.<init>(LoginManager.java:80)
# 	at org.apache.kafka.common.security.authenticator.LoginManager.acquireLoginManager(LoginManager.java:123)
# 	at org.apache.kafka.common.network.SaslChannelBuilder.configure(SaslChannelBuilder.java:179)
# 	at org.apache.kafka.common.network.ChannelBuilders.create(ChannelBuilders.java:233)
# 	at org.apache.kafka.common.network.ChannelBuilders.clientChannelBuilder(ChannelBuilders.java:82)
# 	at org.apache.kafka.clients.ClientUtils.createChannelBuilder(ClientUtils.java:120)
# 	at org.apache.kafka.clients.admin.KafkaAdminClient.createInternal(KafkaAdminClient.java:555)
# 	at org.apache.kafka.clients.admin.KafkaAdminClient.createInternal(KafkaAdminClient.java:516)
# 	at org.apache.kafka.clients.admin.Admin.create(Admin.java:133)
# 	at org.apache.kafka.clients.admin.AdminClient.create(AdminClient.java:39)
# 	at io.confluent.kafka.secretregistry.storage.KafkaStore.createOrVerifySecretTopic(KafkaStore.java:156)
# 	at io.confluent.kafka.secretregistry.storage.KafkaStore.init(KafkaStore.java:108)
# 	at io.confluent.kafka.secretregistry.storage.KafkaSecretRegistry.initStore(KafkaSecretRegistry.java:147)
# 	at io.confluent.connect.secretregistry.rbac.config.provider.InternalSecretConfigProvider.initSecretRegistry(InternalSecretConfigProvider.java:59)
# 	at io.confluent.connect.secretregistry.rbac.config.provider.InternalSecretConfigProvider.configure(InternalSecretConfigProvider.java:70)
# 	at org.apache.kafka.common.config.AbstractConfig.instantiateConfigProviders(AbstractConfig.java:576)
# 	at org.apache.kafka.common.config.AbstractConfig.resolveConfigVariables(AbstractConfig.java:519)
# 	at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:112)
# 	at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:146)
# 	at org.apache.kafka.clients.admin.AdminClientConfig.<init>(AdminClientConfig.java:241)
# 	at org.apache.kafka.clients.admin.Admin.create(Admin.java:143)
# 	at org.apache.kafka.clients.admin.AdminClient.create(AdminClient.java:49)
# 	at io.confluent.admin.utils.ClusterStatus.isKafkaReady(ClusterStatus.java:138)
# 	at io.confluent.admin.utils.cli.KafkaReadyCommand.main(KafkaReadyCommand.java:150)
# Caused by: org.apache.kafka.common.errors.AuthenticationException: Failed to authenticate
# Caused by: io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:23:59,987] WARN Error initializing InternalSecretConfigProvider (io.confluent.connect.secretregistry.rbac.config.provider.InternalSecretConfigProvider:65)
# org.apache.kafka.common.KafkaException: Failed to create new KafkaAdminClient
# 	at org.apache.kafka.clients.admin.KafkaAdminClient.createInternal(KafkaAdminClient.java:587)
# 	at org.apache.kafka.clients.admin.KafkaAdminClient.createInternal(KafkaAdminClient.java:516)
# 	at org.apache.kafka.clients.admin.Admin.create(Admin.java:133)
# 	at org.apache.kafka.clients.admin.AdminClient.create(AdminClient.java:39)
# 	at io.confluent.kafka.secretregistry.storage.KafkaStore.createOrVerifySecretTopic(KafkaStore.java:156)
# 	at io.confluent.kafka.secretregistry.storage.KafkaStore.init(KafkaStore.java:108)
# 	at io.confluent.kafka.secretregistry.storage.KafkaSecretRegistry.initStore(KafkaSecretRegistry.java:147)
# 	at io.confluent.connect.secretregistry.rbac.config.provider.InternalSecretConfigProvider.initSecretRegistry(InternalSecretConfigProvider.java:59)
# 	at io.confluent.connect.secretregistry.rbac.config.provider.InternalSecretConfigProvider.configure(InternalSecretConfigProvider.java:70)
# 	at org.apache.kafka.common.config.AbstractConfig.instantiateConfigProviders(AbstractConfig.java:576)
# 	at org.apache.kafka.common.config.AbstractConfig.resolveConfigVariables(AbstractConfig.java:519)
# 	at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:112)
# 	at org.apache.kafka.common.config.AbstractConfig.<init>(AbstractConfig.java:146)
# 	at org.apache.kafka.clients.admin.AdminClientConfig.<init>(AdminClientConfig.java:241)
# 	at org.apache.kafka.clients.admin.Admin.create(Admin.java:143)
# 	at org.apache.kafka.clients.admin.AdminClient.create(AdminClient.java:49)
# 	at io.confluent.admin.utils.ClusterStatus.isKafkaReady(ClusterStatus.java:138)
# 	at io.confluent.admin.utils.cli.KafkaReadyCommand.main(KafkaReadyCommand.java:150)
# Caused by: org.apache.kafka.common.KafkaException: javax.security.auth.login.LoginException: An internal error occurred while retrieving token from callback handler
# 	at org.apache.kafka.common.network.SaslChannelBuilder.configure(SaslChannelBuilder.java:193)
# 	at org.apache.kafka.common.network.ChannelBuilders.create(ChannelBuilders.java:233)
# 	at org.apache.kafka.common.network.ChannelBuilders.clientChannelBuilder(ChannelBuilders.java:82)
# 	at org.apache.kafka.clients.ClientUtils.createChannelBuilder(ClientUtils.java:120)
# 	at org.apache.kafka.clients.admin.KafkaAdminClient.createInternal(KafkaAdminClient.java:555)
# 	... 17 more
# Caused by: javax.security.auth.login.LoginException: An internal error occurred while retrieving token from callback handler
# 	at org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule.identifyToken(OAuthBearerLoginModule.java:319)
# 	at org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule.login(OAuthBearerLoginModule.java:301)
# 	at java.base/javax.security.auth.login.LoginContext.invoke(LoginContext.java:726)
# 	at java.base/javax.security.auth.login.LoginContext$4.run(LoginContext.java:665)
# 	at java.base/javax.security.auth.login.LoginContext$4.run(LoginContext.java:663)
# 	at java.base/java.security.AccessController.doPrivileged(Native Method)
# 	at java.base/javax.security.auth.login.LoginContext.invokePriv(LoginContext.java:663)
# 	at java.base/javax.security.auth.login.LoginContext.login(LoginContext.java:574)
# 	at org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.login(ExpiringCredentialRefreshingLogin.java:204)
# 	at org.apache.kafka.common.security.oauthbearer.internals.OAuthBearerRefreshingLogin.login(OAuthBearerRefreshingLogin.java:150)
# 	at org.apache.kafka.common.security.authenticator.LoginManager.<init>(LoginManager.java:80)
# 	at org.apache.kafka.common.security.authenticator.LoginManager.acquireLoginManager(LoginManager.java:123)
# 	at org.apache.kafka.common.network.SaslChannelBuilder.configure(SaslChannelBuilder.java:179)
# 	... 21 more
# [2022-01-05 16:24:00,116] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,117] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,341] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,342] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,779] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,779] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:00,946] WARN Creating the secret topic _confluent-secrets using a replication factor of 1, which is less than the desired one of 3. If this is a production environment, it's crucial to add more brokers and increase the replication factor of the topic. (io.confluent.kafka.secretregistry.storage.KafkaStore:191)
# [2022-01-05 16:24:01,627] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:01,628] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:03,295] ERROR Unexpected exception sending HTTP Request. (io.confluent.security.auth.client.rest.RestClient:395)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:03,295] ERROR Error while refreshing active metadata server urls, retrying (io.confluent.security.auth.client.rest.RestClient:181)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-05 16:24:03,298] ERROR Failed to fetch MDS URLs (io.confluent.security.auth.client.rest.RestClient:183)
# io.confluent.security.auth.client.rest.exceptions.RestClientException: Unauthorized; error code: 401
# 	at io.confluent.security.auth.client.rest.RestClient$HTTPRequestSender.lambda$submit$0(RestClient.java:392)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)

