#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"

# WARNING: must be used with a connector build with this code (to activate proxy support):

#   public static class BigQueryBuilder extends GcpClientBuilder<BigQuery> {
#     @Override
#     protected BigQuery doBuild(String project, GoogleCredentials credentials) {

#           HttpHost proxy = new HttpHost("nginx-proxy",8888);
#           //HttpHost proxy = new HttpHost("zazkia", 49998);
#           DefaultHttpClient httpClient = new DefaultHttpClient();

#           httpClient.getParams().setParameter(ConnRoutePNames.DEFAULT_PROXY, proxy);

#           ApacheHttpTransport mHttpTransport = new ApacheHttpTransport(httpClient);

#                HttpTransportFactory hf = new HttpTransportFactory(){
#                          @Override
#                          public HttpTransport create() {
#                               return mHttpTransport;
#                          }
#                     };

#           TransportOptions options = HttpTransportOptions.newBuilder().setHttpTransportFactory(hf).build();

#           BigQueryOptions.Builder builder = BigQueryOptions.newBuilder()
#                .setTransportOptions(options)
#                .setProjectId(project);

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-96554-connection-reset-and-read-timed-out.yml"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "mytopic",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5001",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .

log "Sending a message"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytopic --property parse.key=true --property key.separator=, << EOF
1,{"payload":{"price":25,"product":"foo1","id":100,"quantity":100},"schema":{"fields":[{"optional":false,"type":"int32","field":"id"},{"optional":false,"type":"string","field":"product"},{"optional":false,"type":"int32","field":"quantity"},{"optional":false,"type":"int32","field":"price"}],"type":"struct","name":"orders","optional":false}}
EOF

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.mytopic;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

exit 0

log "Sending a message"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytopic --property parse.key=true --property key.separator=, << EOF
1,{"payload":{"price":25,"product":"foo1","id":100,"quantity":100},"schema":{"fields":[{"optional":false,"type":"int32","field":"id"},{"optional":false,"type":"string","field":"product"},{"optional":false,"type":"int32","field":"quantity"},{"optional":false,"type":"int32","field":"price"}],"type":"struct","name":"orders","optional":false}}
EOF

log "Adding latency from nginx-proxy to connect to simulate a read timeout (hard-coded to 20 seconds)"
add_latency nginx-proxy connect 25000ms


# docker exec -d --privileged --user root connect bash -c 'tcpdump -w /tmp/tcpdump.pcap -i eth0 -s 0 port 443'

# log "Connection timedout"
# docker exec --privileged --user root connect bash -c "iptables -D INPUT -p tcp --sport 443 -j DROP"
