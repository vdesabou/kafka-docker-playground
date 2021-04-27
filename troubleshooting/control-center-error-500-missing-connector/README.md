# Issue with Control Center when connector is missing.

This is to reproduce an upgrade issue from CP Connect 5.x where JDBC connector was included to Connect 6.x where JDBC connector needs to be installed manually (which was not done, hence connector missing).

This test is creating 2 connectors (SFTP and SpoolDir, type does not matter here), then to simulate the JDBC connector issue, I remove the spooldir connector:

Remove `/usr/share/confluent-hub-components/jcustenborder-kafka-connect-spooldir`:

```bash
$ docker exec connect rm -rf /usr/share/confluent-hub-components/jcustenborder-kafka-connect-spooldir
````

Restart connect container:

```bash
$ docker container restart connect
```

After that if I check the connect cluster status in Control Center (make sure to refresh the browser), I see:

![c3 error](screenshot1.jpg)

Problem here is that one connector failing should not prevent the connect cluster to appear.

Error 500 in Control-Center:

```log
[2021-04-27 11:58:51,044] INFO 172.23.0.1 - - [27/Apr/2021:11:58:51 +0000] "GET /api/connect/connect-default/connectors?expand=status&expand=info HTTP/1.1" 500 4609  9 (io.confluent.rest-utils.requests)
```

Stack trace in Connect:

```log
[2021-04-27 11:59:56,620] ERROR Uncaught exception in REST call to /connectors (org.apache.kafka.connect.runtime.rest.errors.ConnectExceptionMapper)
org.apache.kafka.connect.errors.ConnectException: Failed to find any class that implements Connector and which name matches com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector, available connectors are: PluginDesc{klass=class io.confluent.connect.sftp.SftpBinaryFileSourceConnector, name='io.confluent.connect.sftp.SftpBinaryFileSourceConnector', version='0.0.0.0', encodedVersion=0.0.0.0, type=source, typeName='source', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class io.confluent.connect.sftp.SftpCsvSourceConnector, name='io.confluent.connect.sftp.SftpCsvSourceConnector', version='0.0.0.0', encodedVersion=0.0.0.0, type=source, typeName='source', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class io.confluent.connect.sftp.SftpJsonSourceConnector, name='io.confluent.connect.sftp.SftpJsonSourceConnector', version='0.0.0.0', encodedVersion=0.0.0.0, type=source, typeName='source', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class io.confluent.connect.sftp.SftpSchemaLessJsonSourceConnector, name='io.confluent.connect.sftp.SftpSchemaLessJsonSourceConnector', version='0.0.0.0', encodedVersion=0.0.0.0, type=source, typeName='source', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class io.confluent.connect.sftp.SftpSinkConnector, name='io.confluent.connect.sftp.SftpSinkConnector', version='unknown', encodedVersion=unknown, type=sink, typeName='sink', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class io.confluent.connect.storage.tools.SchemaSourceConnector, name='io.confluent.connect.storage.tools.SchemaSourceConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='file:/usr/share/confluent-hub-components/confluentinc-kafka-connect-sftp/lib/'}, PluginDesc{klass=class org.apache.kafka.connect.file.FileStreamSinkConnector, name='org.apache.kafka.connect.file.FileStreamSinkConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=sink, typeName='sink', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.file.FileStreamSourceConnector, name='org.apache.kafka.connect.file.FileStreamSourceConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.mirror.MirrorCheckpointConnector, name='org.apache.kafka.connect.mirror.MirrorCheckpointConnector', version='1', encodedVersion=1, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.mirror.MirrorHeartbeatConnector, name='org.apache.kafka.connect.mirror.MirrorHeartbeatConnector', version='1', encodedVersion=1, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.mirror.MirrorSourceConnector, name='org.apache.kafka.connect.mirror.MirrorSourceConnector', version='1', encodedVersion=1, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.MockConnector, name='org.apache.kafka.connect.tools.MockConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=connector, typeName='connector', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.MockSinkConnector, name='org.apache.kafka.connect.tools.MockSinkConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=sink, typeName='sink', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.MockSourceConnector, name='org.apache.kafka.connect.tools.MockSourceConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.SchemaSourceConnector, name='org.apache.kafka.connect.tools.SchemaSourceConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.VerifiableSinkConnector, name='org.apache.kafka.connect.tools.VerifiableSinkConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='classpath'}, PluginDesc{klass=class org.apache.kafka.connect.tools.VerifiableSourceConnector, name='org.apache.kafka.connect.tools.VerifiableSourceConnector', version='6.1.1-ce', encodedVersion=6.1.1-ce, type=source, typeName='source', location='classpath'}
        at org.apache.kafka.connect.runtime.isolation.Plugins.connectorClass(Plugins.java:208)
        at org.apache.kafka.connect.runtime.isolation.Plugins.newConnector(Plugins.java:180)
        at org.apache.kafka.connect.runtime.AbstractHerder.getConnector(AbstractHerder.java:576)
        at org.apache.kafka.connect.runtime.AbstractHerder.connectorTypeForClass(AbstractHerder.java:587)
        at org.apache.kafka.connect.runtime.AbstractHerder.connectorStatus(AbstractHerder.java:278)
        at org.apache.kafka.connect.runtime.rest.resources.ConnectorsResource.listConnectors(ConnectorsResource.java:126)
        at jdk.internal.reflect.GeneratedMethodAccessor2.invoke(Unknown Source)
        at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
        at java.base/java.lang.reflect.Method.invoke(Method.java:566)
        at org.glassfish.jersey.server.model.internal.ResourceMethodInvocationHandlerFactory.lambda$static$0(ResourceMethodInvocationHandlerFactory.java:52)
        at org.glassfish.jersey.server.model.internal.AbstractJavaResourceMethodDispatcher$1.run(AbstractJavaResourceMethodDispatcher.java:124)
        at org.glassfish.jersey.server.model.internal.AbstractJavaResourceMethodDispatcher.invoke(AbstractJavaResourceMethodDispatcher.java:167)
        at org.glassfish.jersey.server.model.internal.JavaResourceMethodDispatcherProvider$ResponseOutInvoker.doDispatch(JavaResourceMethodDispatcherProvider.java:176)
        at org.glassfish.jersey.server.model.internal.AbstractJavaResourceMethodDispatcher.dispatch(AbstractJavaResourceMethodDispatcher.java:79)
        at org.glassfish.jersey.server.model.ResourceMethodInvoker.invoke(ResourceMethodInvoker.java:469)
        at org.glassfish.jersey.server.model.ResourceMethodInvoker.apply(ResourceMethodInvoker.java:391)
        at org.glassfish.jersey.server.model.ResourceMethodInvoker.apply(ResourceMethodInvoker.java:80)
        at org.glassfish.jersey.server.ServerRuntime$1.run(ServerRuntime.java:253)
        at org.glassfish.jersey.internal.Errors$1.call(Errors.java:248)
        at org.glassfish.jersey.internal.Errors$1.call(Errors.java:244)
        at org.glassfish.jersey.internal.Errors.process(Errors.java:292)
        at org.glassfish.jersey.internal.Errors.process(Errors.java:274)
        at org.glassfish.jersey.internal.Errors.process(Errors.java:244)
        at org.glassfish.jersey.process.internal.RequestScope.runInScope(RequestScope.java:265)
        at org.glassfish.jersey.server.ServerRuntime.process(ServerRuntime.java:232)
        at org.glassfish.jersey.server.ApplicationHandler.handle(ApplicationHandler.java:680)
        at org.glassfish.jersey.servlet.WebComponent.serviceImpl(WebComponent.java:394)
        at org.glassfish.jersey.servlet.WebComponent.service(WebComponent.java:346)
        at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:366)
        at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:319)
        at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:205)
        at org.eclipse.jetty.servlet.ServletHolder.handle(ServletHolder.java:791)
        at org.eclipse.jetty.servlet.ServletHandler.doHandle(ServletHandler.java:550)
        at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:233)
        at org.eclipse.jetty.server.session.SessionHandler.doHandle(SessionHandler.java:1624)
        at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:233)
        at org.eclipse.jetty.server.handler.ContextHandler.doHandle(ContextHandler.java:1435)
        at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:188)
        at org.eclipse.jetty.servlet.ServletHandler.doScope(ServletHandler.java:501)
        at org.eclipse.jetty.server.session.SessionHandler.doScope(SessionHandler.java:1594)
        at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:186)
        at org.eclipse.jetty.server.handler.ContextHandler.doScope(ContextHandler.java:1350)
        at org.eclipse.jetty.server.handler.ScopedHandler.handle(ScopedHandler.java:141)
        at org.eclipse.jetty.server.handler.ContextHandlerCollection.handle(ContextHandlerCollection.java:234)
        at org.eclipse.jetty.server.handler.StatisticsHandler.handle(StatisticsHandler.java:179)
        at org.eclipse.jetty.server.handler.HandlerWrapper.handle(HandlerWrapper.java:127)
        at org.eclipse.jetty.server.Server.handle(Server.java:516)
        at org.eclipse.jetty.server.HttpChannel.lambda$handle$1(HttpChannel.java:388)
        at org.eclipse.jetty.server.HttpChannel.dispatch(HttpChannel.java:633)
        at org.eclipse.jetty.server.HttpChannel.handle(HttpChannel.java:380)
        at org.eclipse.jetty.server.HttpConnection.onFillable(HttpConnection.java:279)
        at org.eclipse.jetty.io.AbstractConnection$ReadCallback.succeeded(AbstractConnection.java:311)
        at org.eclipse.jetty.io.FillInterest.fillable(FillInterest.java:105)
        at org.eclipse.jetty.io.ChannelEndPoint$1.run(ChannelEndPoint.java:104)
        at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.runTask(EatWhatYouKill.java:336)
        at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.doProduce(EatWhatYouKill.java:313)
        at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.tryProduce(EatWhatYouKill.java:171)
        at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.run(EatWhatYouKill.java:129)
        at org.eclipse.jetty.util.thread.ReservedThreadExecutor$ReservedThread.run(ReservedThreadExecutor.java:383)
        at org.eclipse.jetty.util.thread.QueuedThreadPool.runJob(QueuedThreadPool.java:882)
        at org.eclipse.jetty.util.thread.QueuedThreadPool$Runner.run(QueuedThreadPool.java:1036)
        at java.base/java.lang.Thread.run(Thread.java:834)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])