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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-auth.yml"

wait_service 'http://localhost:7200/protocol'


log "Creating http-source connector"
playground connector create-or-update --connector http-source << EOF
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

playground topic produce -t test --nb-messages 10  << 'EOF'
<urn:a> <urn:b> <urn:c> .
EOF



