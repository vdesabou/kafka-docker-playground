#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -f ${PWD}/GoogleBigQueryJDBC42/GoogleBigQueryJDBC42.jar ]
then
    mkdir -p GoogleBigQueryJDBC42
    cd GoogleBigQueryJDBC42
    wget -q https://storage.googleapis.com/simba-bq-release/jdbc/SimbaBigQueryJDBC42-1.3.2.1003.zip
    unzip SimbaBigQueryJDBC42-1.3.2.1003.zip
    cd -
fi

cd ../../connect/connect-jdbc-gcp-bigquery-source
GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "❌ either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi
cd -

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG_BASE}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"
sleep 1
# https://github.com/GoogleCloudPlatform/terraform-google-secured-data-warehouse/issues/35
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $GCP_PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" mk --dataset --label cflt_managed_by:user --label cflt_managed_id:"$USER" --description "used by playground" "$DATASET"

log "Create table $GCP_PROJECT:$DATASET.customers"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq  mk --table --description "customers table" $GCP_PROJECT:$DATASET.customers id:INTEGER,first_name:STRING,last_name:STRING,email:STRING,updated_at:TIMESTAMP

log "Insert a row"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" query --nouse_legacy_sql "INSERT INTO $DATASET.customers(first_name,last_name,email,updated_at) VALUES ('Sally','Thomas','sally.thomas@acme.com', CURRENT_TIMESTAMP());" > /tmp/result.log  2>&1
cat /tmp/result.log


cd ../../connect/connect-jdbc-gcp-bigquery-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/threetenbp-1.6.4.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/threetenbp-1.6.4.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/slf4j-api-1.7.36.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/slf4j-api-1.7.36.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/protobuf-java-util-3.21.9.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/protobuf-java-util-3.21.9.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/protobuf-java-3.21.9.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/protobuf-java-3.21.9.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/proto-google-iam-v1-1.6.7.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/proto-google-iam-v1-1.6.7.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/proto-google-common-protos-2.10.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/proto-google-common-protos-2.10.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/proto-google-cloud-bigquerystorage-v1beta2-0.150.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/proto-google-cloud-bigquerystorage-v1beta2-0.150.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/proto-google-cloud-bigquerystorage-v1beta1-0.150.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/proto-google-cloud-bigquerystorage-v1beta1-0.150.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/proto-google-cloud-bigquerystorage-v1-2.26.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/proto-google-cloud-bigquerystorage-v1-2.26.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/perfmark-api-0.25.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/perfmark-api-0.25.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/opencensus-contrib-http-util-0.31.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/opencensus-contrib-http-util-0.31.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/opencensus-api-0.31.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/opencensus-api-0.31.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/jsr305-3.0.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/jsr305-3.0.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/json-20200518.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/json-20200518.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/joda-time-2.10.10.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/joda-time-2.10.10.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/javax.annotation-api-1.3.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/javax.annotation-api-1.3.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/jackson-databind-2.12.7.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/jackson-databind-2.12.7.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/jackson-core-2.12.7.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/jackson-core-2.12.7.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/jackson-annotations-2.12.7.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/jackson-annotations-2.12.7.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/j2objc-annotations-1.3.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/j2objc-annotations-1.3.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/httpcore-4.4.15.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/httpcore-4.4.15.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/httpclient-4.5.13.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/httpclient-4.5.13.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/guava-31.1-jre.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/guava-31.1-jre.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/gson-2.10.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/gson-2.10.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-stub-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-stub-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-protobuf-lite-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-protobuf-lite-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-protobuf-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-protobuf-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-netty-shaded-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-netty-shaded-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-grpclb-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-grpclb-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-googleapis-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-googleapis-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-google-cloud-bigquerystorage-v1beta2-0.150.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-google-cloud-bigquerystorage-v1beta2-0.150.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-google-cloud-bigquerystorage-v1beta1-0.150.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-google-cloud-bigquerystorage-v1beta1-0.150.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-google-cloud-bigquerystorage-v1-2.26.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-google-cloud-bigquerystorage-v1-2.26.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-core-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-core-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-context-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-context-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-auth-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-auth-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-api-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-api-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/grpc-alts-1.50.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/grpc-alts-1.50.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-oauth-client-1.34.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-oauth-client-1.34.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-http-client-gson-1.42.3.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-http-client-gson-1.42.3.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-http-client-apache-v2-1.42.3.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-http-client-apache-v2-1.42.3.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-http-client-1.42.3.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-http-client-1.42.3.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-cloud-core-2.8.27.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-cloud-core-2.8.27.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-cloud-bigquerystorage-2.26.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-cloud-bigquerystorage-2.26.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-auth-library-oauth2-http-1.12.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-auth-library-oauth2-http-1.12.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-auth-library-credentials-1.12.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-auth-library-credentials-1.12.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-api-services-bigquery-v2-rev20221028-2.0.0.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-api-services-bigquery-v2-rev20221028-2.0.0.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/google-api-client-2.1.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/google-api-client-2.1.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/gax-grpc-2.19.5.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/gax-grpc-2.19.5.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/gax-2.19.5.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/gax-2.19.5.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/failureaccess-1.0.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/failureaccess-1.0.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/error_prone_annotations-2.16.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/error_prone_annotations-2.16.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/conscrypt-openjdk-uber-2.5.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/conscrypt-openjdk-uber-2.5.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/commons-logging-1.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/commons-logging-1.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/commons-compress-1.21.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/commons-compress-1.21.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/commons-codec-1.15.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/commons-codec-1.15.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/avro-1.11.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/avro-1.11.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/auto-value-annotations-1.10.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/auto-value-annotations-1.10.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/auto-value-1.10.1.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/auto-value-1.10.1.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/api-common-2.2.2.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/api-common-2.2.2.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/annotations-4.1.1.4.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/annotations-4.1.1.4.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/animal-sniffer-annotations-1.22.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/animal-sniffer-annotations-1.22.jar
cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/GoogleBigQueryJDBC42.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/GoogleBigQueryJDBC42.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Creating JDBC GCP BigQuery Source connector"
playground connector create-or-update --connector jdbc-gcp-bigquery-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;ProjectId=$GCP_PROJECT;OAuthType=0;OAuthServiceAcctEmail=$SERVICE_ACCOUNT_EMAIL;OAuthPvtKeyPath=/tmp/keyfile.json;DefaultDataset=$DATASET;IgnoreTransactions=1;",
    "table.whitelist": "customers",
    "mode": "bulk",
    "topic.prefix": "gcp-",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "validate.non.null": "false"
}
EOF

#     "mode": "timestamp",
#     "timestamp.column.name": "updated_at",
# [2023-07-11 15:11:49,341] INFO [jdbc-gcp-bigquery-source|task-0] Begin using SQL query: SELECT * FROM `vincent-de-saboulin-lab`.`pgvsaboulinds740`.`customers` WHERE `vincent-de-saboulin-lab`.`pgvsaboulinds740`.`customers`.`updated_at` > ? AND `vincent-de-saboulin-lab`.`pgvsaboulinds740`.`customers`.`updated_at` < ? ORDER BY `vincent-de-saboulin-lab`.`pgvsaboulinds740`.`customers`.`updated_at` ASC (io.confluent.connect.jdbc.source.TableQuerier:182)
# [2023-07-11 15:11:49,822] ERROR [jdbc-gcp-bigquery-source|task-0] SQL exception while running query for table: TimestampTableQuerier{table="vincent-de-saboulin-lab"."pgvsaboulinds740"."customers", query='null', topicPrefix='gcp-', timestampColumns=[updated_at]}, java.sql.SQLException: [Simba][BigQueryJDBCDriver](100032) Error executing query job. Message: 400 Bad Request
# POST https://bigquery.googleapis.com/bigquery/v2/projects/vincent-de-saboulin-lab/jobs
# {
#   "code": 400,
#   "errors": [
#     {
#       "domain": "global",
#       "location": "q",
#       "locationType": "parameter",
#       "message": "Unrecognized name: `vincent-de-saboulin-lab` at [1:78]",
#       "reason": "invalidQuery"
#     }
#   ],
#   "message": "Unrecognized name: `vincent-de-saboulin-lab` at [1:78]",
#   "status": "INVALID_ARGUMENT"
# }. Attempting retry 1 of -1 attempts. (io.confluent.connect.jdbc.source.JdbcSourceTask:455)

playground topic consume