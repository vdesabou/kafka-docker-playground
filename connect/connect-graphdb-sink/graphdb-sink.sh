#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

GRAPHDB_SINK_CONNECTOR_ZIP="kafka-sink-graphdb-plugin.zip"
export CONNECTOR_ZIP="$PWD/$GRAPHDB_SINK_CONNECTOR_ZIP"

source ${DIR}/../../scripts/utils.sh


get_3rdparty_file "$GRAPHDB_SINK_CONNECTOR_ZIP"

if [ ! -f ${PWD}/$GRAPHDB_SINK_CONNECTOR_ZIP ]
then
     logerror "ERROR: ${PWD}/$GRAPHDB_SINK_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
     exit 1
fi

function wait_service {
	printf "waiting for $1"
	until curl -s --fail -m 1 "$1" &> /dev/null; do
		sleep 1
		printf '.'
	done
	echo
}

function create_graphdb_repo {
if ! curl --fail -X GET --header 'Accept: application/json' http://localhost:7200/rest/repositories/test &> /dev/null; then
     curl 'http://localhost:7200/rest/repositories' \
          -H 'Accept: application/json, text/plain, */*' \
          -H 'Content-Type: application/json;charset=UTF-8' \
          -d '{"id": "test", "params": {"imports": {"name": "imports", "label": "Imported RDF files('\'';'\'' delimited)", "value": ""}, "defaultNS": {"name": "defaultNS", "label": "Default namespaces for imports('\'';'\'' delimited)", "value": ""}}, "title": "", "type": "graphdb", "location": ""}'
fi
}


PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_service 'http://localhost:7200/protocol'

create_graphdb_repo

log "Creating graphdb-sink connector"
playground connector create-or-update --connector graphdb-sink << EOF
{
     "connector.class":"com.ontotext.kafka.GraphDBSinkConnector",
     "key.converter": "com.ontotext.kafka.convert.DirectRDFConverter",
     "value.converter": "com.ontotext.kafka.convert.DirectRDFConverter",
     "value.converter.schemas.enable": "false",
     "topics":"test",
     "tasks.max":"1",
     "_offset.storage.file.filename": "/tmp/storage",
     "graphdb.server.url": "http://graphdb:7200",
     "graphdb.server.repository": "test",
     "graphdb.batch.size": 64,
     "graphdb.batch.commit.limit.ms": 1000,
     "graphdb.auth.type": "NONE",
     "graphdb.update.type": "ADD",
     "graphdb.update.rdf.format": "nq"
}
EOF

# [2023-12-15 14:51:28,134] ERROR [graphdb-sink|worker] [Worker clientId=connect-adminclient-producer, groupId=connect-cluster] Failed to start connector 'graphdb-sink' (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1928)
# org.apache.kafka.connect.errors.ConnectException: Failed to start connector: graphdb-sink
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$startConnector$36(DistributedHerder.java:1899)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:361)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:145)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:123)
#         at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:181)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to transition connector graphdb-sink to state STARTED
#         ... 9 more
# Caused by: java.lang.NoSuchMethodError: 'void org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.<init>(long, long, org.apache.kafka.connect.runtime.errors.ToleranceType, org.apache.kafka.common.utils.Time)'
#         at com.ontotext.kafka.operation.GraphDBOperator.<init>(GraphDBOperator.java:34)
#         at com.ontotext.kafka.service.GraphDBService.initialize(GraphDBService.java:45)
#         at com.ontotext.kafka.GraphDBSinkConnector.start(GraphDBSinkConnector.java:58)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:193)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:218)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:377)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:358)
#         ... 8 more

playground connector restart

playground topic produce -t test --nb-messages 10  << 'EOF'
<urn:a> <urn:b> <urn:c> .
EOF

log "go to http://127.0.0.1:7200/sparql select the test repository and execute select * where { <urn:a> ?p ?o  . }"


