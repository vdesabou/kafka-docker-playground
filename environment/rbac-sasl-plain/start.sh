#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
echo "Generating public and private keys for token signing"
mkdir -p ./conf
openssl genrsa -out ./conf/keypair.pem 2048
openssl rsa -in ./conf/keypair.pem -outform PEM -pubout -out ./conf/public.pem

# Bring up base cluster and Confluent CLI
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d zookeeper broker tools openldap
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml up -d zookeeper broker tools openldap
fi

# Verify Kafka brokers have started
MAX_WAIT=30
log "Waiting up to $MAX_WAIT seconds for Kafka brokers to be registered in ZooKeeper"
retrycmd $MAX_WAIT 5 host_check_kafka_cluster_registered || exit 1

# Verify MDS has started
MAX_WAIT=60
log "Waiting up to $MAX_WAIT seconds for MDS to start"
retrycmd $MAX_WAIT 5 host_check_mds_up || exit 1
sleep 5

log "Available LDAP users:"
docker exec openldap ldapsearch -x -h localhost -b dc=confluentdemo,dc=io -D "cn=admin,dc=confluentdemo,dc=io" -w admin | grep uid:

log "Creating role bindings for principals"
docker exec -i tools bash -c "/tmp/helper/create-role-bindings.sh"

if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d  schema-registry replicator-for-jar-transfer connect control-center
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml up -d schema-registry replicator-for-jar-transfer connect control-center
fi

# C3:
# [2020-03-26 13:27:48,565] ERROR Request Failed with exception  (io.confluent.rest.exceptions.DebuggableExceptionMapper)
# javax.ws.rs.ForbiddenException: must have view access
# 	at io.confluent.controlcenter.rest.ClusterConverter.verifyKafkaClusterVisibility(ClusterConverter.java:52)
# 	at io.confluent.controlcenter.rest.ClusterConverter.access$000(ClusterConverter.java:25)
# 	at io.confluent.controlcenter.rest.ClusterConverter$4.fromString(ClusterConverter.java:144)
# 	at org.glassfish.jersey.server.internal.inject.AbstractParamValueExtractor.convert(AbstractParamValueExtractor.java:116)
# 	at org.glassfish.jersey.server.internal.inject.AbstractParamValueExtractor.fromString(AbstractParamValueExtractor.java:107)
# 	at org.glassfish.jersey.server.internal.inject.SingleValueExtractor.extract(SingleValueExtractor.java:61)
# 	at org.glassfish.jersey.server.internal.inject.PathParamValueParamProvider$PathParamValueProvider.apply(PathParamValueParamProvider.java:92)
# 	at org.glassfish.jersey.server.internal.inject.PathParamValueParamProvider$PathParamValueProvider.apply(PathParamValueParamProvider.java:79)
# 	at org.glassfish.jersey.server.spi.internal.ParamValueFactoryWithSource.apply(ParamValueFactoryWithSource.java:50)
# 	at org.glassfish.jersey.server.spi.internal.ParameterValueHelper.getParameterValues(ParameterValueHelper.java:64)
# 	at org.glassfish.jersey.server.model.internal.JavaResourceMethodDispatcherProvider$AbstractMethodParamInvoker.getParamValues(JavaResourceMethodDispatcherProvider.java:109)
# 	at org.glassfish.jersey.server.model.internal.JavaResourceMethodDispatcherProvider$TypeOutInvoker.doDispatch(JavaResourceMethodDispatcherProvider.java:219)
# 	at org.glassfish.jersey.server.model.internal.AbstractJavaResourceMethodDispatcher.dispatch(AbstractJavaResourceMethodDispatcher.java:79)
# 	at org.glassfish.jersey.server.model.ResourceMethodInvoker.invoke(ResourceMethodInvoker.java:469)
# 	at org.glassfish.jersey.server.model.ResourceMethodInvoker.apply(ResourceMethodInvoker.java:391)
# 	at org.glassfish.jersey.server.model.ResourceMethodInvoker.apply(ResourceMethodInvoker.java:80)
# 	at org.glassfish.jersey.server.ServerRuntime$1.run(ServerRuntime.java:253)
# 	at org.glassfish.jersey.internal.Errors$1.call(Errors.java:248)
# 	at org.glassfish.jersey.internal.Errors$1.call(Errors.java:244)
# 	at org.glassfish.jersey.internal.Errors.process(Errors.java:292)
# 	at org.glassfish.jersey.internal.Errors.process(Errors.java:274)
# 	at org.glassfish.jersey.internal.Errors.process(Errors.java:244)
# 	at org.glassfish.jersey.process.internal.RequestScope.runInScope(RequestScope.java:265)
# 	at org.glassfish.jersey.server.ServerRuntime.process(ServerRuntime.java:232)
# 	at org.glassfish.jersey.server.ApplicationHandler.handle(ApplicationHandler.java:679)
# 	at org.glassfish.jersey.servlet.WebComponent.serviceImpl(WebComponent.java:392)
# 	at org.glassfish.jersey.servlet.ServletContainer.serviceImpl(ServletContainer.java:385)
# 	at org.glassfish.jersey.servlet.ServletContainer.doFilter(ServletContainer.java:560)
# 	at org.glassfish.jersey.servlet.ServletContainer.doFilter(ServletContainer.java:501)
# 	at org.glassfish.jersey.servlet.ServletContainer.doFilter(ServletContainer.java:438)
# 	at org.eclipse.jetty.servlet.ServletHandler$CachedChain.doFilter(ServletHandler.java:1591)
# 	at org.eclipse.jetty.servlet.ServletHandler.doHandle(ServletHandler.java:542)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.handle(ScopedHandler.java:143)
# 	at org.eclipse.jetty.security.SecurityHandler.handle(SecurityHandler.java:501)
# 	at org.eclipse.jetty.server.handler.HandlerWrapper.handle(HandlerWrapper.java:127)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:235)
# 	at org.eclipse.jetty.server.session.SessionHandler.doHandle(SessionHandler.java:1581)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:233)
# 	at org.eclipse.jetty.server.handler.ContextHandler.doHandle(ContextHandler.java:1307)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:188)
# 	at org.eclipse.jetty.servlet.ServletHandler.doScope(ServletHandler.java:482)
# 	at org.eclipse.jetty.server.session.SessionHandler.doScope(SessionHandler.java:1549)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:186)
# 	at org.eclipse.jetty.server.handler.ContextHandler.doScope(ContextHandler.java:1204)
# 	at org.eclipse.jetty.server.handler.ScopedHandler.handle(ScopedHandler.java:141)
# 	at org.eclipse.jetty.server.handler.HandlerCollection.handle(HandlerCollection.java:146)
# 	at org.eclipse.jetty.server.handler.HandlerCollection.handle(HandlerCollection.java:146)
# 	at org.eclipse.jetty.server.handler.StatisticsHandler.handle(StatisticsHandler.java:173)
# 	at org.eclipse.jetty.server.handler.ContextHandlerCollection.handle(ContextHandlerCollection.java:221)
# 	at org.eclipse.jetty.server.handler.gzip.GzipHandler.handle(GzipHandler.java:772)
# 	at org.eclipse.jetty.server.handler.HandlerWrapper.handle(HandlerWrapper.java:127)
# 	at org.eclipse.jetty.server.Server.handle(Server.java:494)
# 	at org.eclipse.jetty.server.HttpChannel.handle(HttpChannel.java:374)
# 	at org.eclipse.jetty.server.HttpConnection.onFillable(HttpConnection.java:268)
# 	at org.eclipse.jetty.io.AbstractConnection$ReadCallback.succeeded(AbstractConnection.java:311)
# 	at org.eclipse.jetty.io.FillInterest.fillable(FillInterest.java:103)
# 	at org.eclipse.jetty.io.ChannelEndPoint$2.run(ChannelEndPoint.java:117)
# 	at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.runTask(EatWhatYouKill.java:336)
# 	at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.doProduce(EatWhatYouKill.java:313)
# 	at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.tryProduce(EatWhatYouKill.java:171)
# 	at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.run(EatWhatYouKill.java:129)
# 	at org.eclipse.jetty.util.thread.ReservedThreadExecutor$ReservedThread.run(ReservedThreadExecutor.java:367)
# 	at org.eclipse.jetty.util.thread.QueuedThreadPool.runJob(QueuedThreadPool.java:782)
# 	at org.eclipse.jetty.util.thread.QueuedThreadPool$Runner.run(QueuedThreadPool.java:918)
# 	at java.lang.Thread.run(Thread.java:748)

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@