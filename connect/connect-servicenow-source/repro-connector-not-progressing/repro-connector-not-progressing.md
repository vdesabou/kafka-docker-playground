Before running the test go to ServiceNow UI and select `Scripts Background`

Execute the following:

```java
for(var i = 0 ; i < 100 ; i++)
{
var gr = new GlideRecord('incident');
gr.initialize();
gr.caller_id = '62826bf03710200044e0bfc8bcbe5df1';
gr.short_description = 'repro-connector-not-progressing';
gr.insert();
}
```

![1](1.jpg)

Then:


```java
var inc = new GlideRecord(“incident”);
inc.addEncodedQuery(“short_description=repro-connector-not-progressing”);
inc.query();
while (inc.next()) {
 inc.work_notes = “Updating all repro-connector-not-progressing incidents“;
 inc.autoSysFields(true);
 inc.setWorkflow(false);
 inc.update();
}
```

You should see multiple incidents (more than 10 to reproduce, as `batch.max.rows` is set to 10) updated in same second:

![2](2.jpg)


In logs, I see:

```log
[2021-07-16 06:16:49,772] DEBUG Check connectivity of url: https://dev71747.service-now.com/api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:49,776] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:49,777] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_limit=1 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:52,317] INFO WorkerSourceTask{id=servicenow-source-0} Source task finished initialization and start (org.apache.kafka.connect.runtime.WorkerSourceTask)
[2021-07-16 06:16:52,319] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:52,320] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2000:00:00%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:52,937] DEBUG Collected 10 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:52,956] INFO creating interceptor (io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor)
[2021-07-16 06:16:52,958] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:52,959] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:53,009] INFO MonitoringInterceptorConfig values:
	confluent.monitoring.interceptor.publishMs = 15000
	confluent.monitoring.interceptor.topic = _confluent-monitoring
 (io.confluent.monitoring.clients.interceptor.MonitoringInterceptorConfig)
[2021-07-16 06:16:53,040] INFO ProducerConfig values:
	acks = -1
	batch.size = 16384
	bootstrap.servers = [broker:9092]
	buffer.memory = 33554432
	client.dns.lookup = use_all_dns_ips
	client.id = confluent.monitoring.interceptor.connect-worker-producer
	compression.type = lz4
	connections.max.idle.ms = 540000
	delivery.timeout.ms = 120000
	enable.idempotence = false
	interceptor.classes = []
	internal.auto.downgrade.txn.commit = false
	key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
	linger.ms = 500
	max.block.ms = 60000
	max.in.flight.requests.per.connection = 1
	max.request.size = 10485760
	metadata.max.age.ms = 300000
	metadata.max.idle.ms = 300000
	metric.reporters = []
	metrics.num.samples = 2
	metrics.recording.level = INFO
	metrics.sample.window.ms = 30000
	partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
	receive.buffer.bytes = 32768
	reconnect.backoff.max.ms = 1000
	reconnect.backoff.ms = 50
	request.timeout.ms = 30000
	retries = 2147483647
	retry.backoff.ms = 500
	sasl.client.callback.handler.class = null
	sasl.jaas.config = null
	sasl.kerberos.kinit.cmd = /usr/bin/kinit
	sasl.kerberos.min.time.before.relogin = 60000
	sasl.kerberos.service.name = null
	sasl.kerberos.ticket.renew.jitter = 0.05
	sasl.kerberos.ticket.renew.window.factor = 0.8
	sasl.login.callback.handler.class = null
	sasl.login.class = null
	sasl.login.refresh.buffer.seconds = 300
	sasl.login.refresh.min.period.seconds = 60
	sasl.login.refresh.window.factor = 0.8
	sasl.login.refresh.window.jitter = 0.05
	sasl.mechanism = GSSAPI
	security.protocol = PLAINTEXT
	security.providers = null
	send.buffer.bytes = 131072
	socket.connection.setup.timeout.max.ms = 30000
	socket.connection.setup.timeout.ms = 10000
	ssl.cipher.suites = null
	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
	ssl.endpoint.identification.algorithm = https
	ssl.engine.factory.class = null
	ssl.key.password = null
	ssl.keymanager.algorithm = SunX509
	ssl.keystore.certificate.chain = null
	ssl.keystore.key = null
	ssl.keystore.location = null
	ssl.keystore.password = null
	ssl.keystore.type = JKS
	ssl.protocol = TLSv1.3
	ssl.provider = null
	ssl.secure.random.implementation = null
	ssl.trustmanager.algorithm = PKIX
	ssl.truststore.certificates = null
	ssl.truststore.location = null
	ssl.truststore.password = null
	ssl.truststore.type = JKS
	transaction.timeout.ms = 60000
	transactional.id = null
	value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
 (org.apache.kafka.clients.producer.ProducerConfig)
[2021-07-16 06:16:53,044] INFO Kafka version: 6.2.0-ce (org.apache.kafka.common.utils.AppInfoParser)
[2021-07-16 06:16:53,044] INFO Kafka commitId: 5c753752ae1445a1 (org.apache.kafka.common.utils.AppInfoParser)
[2021-07-16 06:16:53,044] INFO Kafka startTimeMs: 1626416213044 (org.apache.kafka.common.utils.AppInfoParser)
[2021-07-16 06:16:53,047] INFO interceptor=confluent.monitoring.interceptor.connect-worker-producer created for client_id=connect-worker-producer client_type=PRODUCER session= cluster=0VRPR79iQhKpg9pX-kUnow (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor)
[2021-07-16 06:16:53,051] INFO [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer] Cluster ID: 0VRPR79iQhKpg9pX-kUnow (org.apache.kafka.clients.Metadata)
[2021-07-16 06:16:53,366] DEBUG Collected 6 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:53,371] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:53,371] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:53,716] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:53,716] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:53,716] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,066] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:54,066] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,066] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,373] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:54,373] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,373] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,712] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:54,712] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:54,712] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,055] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:55,055] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,055] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,403] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:55,404] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,404] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,758] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:55,758] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:55,758] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,109] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:56,110] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,110] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,483] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:56,483] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,484] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,834] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:56,835] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:56,835] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,178] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:57,178] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,179] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,526] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:57,527] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,527] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,872] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:57,873] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:57,873] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,220] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:58,221] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,221] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,577] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:58,577] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,577] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,952] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:58,952] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:58,952] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:59,298] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:59,299] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:59,299] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:59,664] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:16:59,665] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:16:59,665] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,018] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:17:00,019] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,019] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,366] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:17:00,366] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,366] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,709] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:17:00,710] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:00,710] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:01,060] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:17:01,060] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:01,061] DEBUG Calling GET on https://dev71747.service-now.com/api/now/table/incident?sysparm_query=sys_updated_on%3E%3D2021-07-16%2006:15:04%5EORDERBYsys_updated_on&sysparm_limit=10 (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
[2021-07-16 06:17:01,412] DEBUG Collected 0 records, new offset at <2021-07-16T06:15:04, null, null> (io.confluent.connect.servicenow.ServiceNowSourceTask)
[2021-07-16 06:17:01,412] DEBUG Launch HTTP request to following URL: /api/now/table/incident (io.confluent.connect.servicenow.rest.ServiceNowClientImpl)
```
