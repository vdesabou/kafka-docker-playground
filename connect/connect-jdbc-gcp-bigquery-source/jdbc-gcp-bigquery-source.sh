#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
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

# unique per environment, see cloud_resource_environment_id
DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG_BASE}$(cloud_resource_environment_id)
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
if connect_cp_version_greater_than_8
then
    # CP 8+ worker classpath already ships grpc, gax, google-auth, google-http-client, guava, protobuf, opencensus, etc.
    # bundling the driver's older copies in the plugin breaks with:
    # Storage override failed to initialize (io.grpc.override.ContextStorageOverride from opentelemetry-grpc-1.6 on the worker classpath)
    # or LinkageError: loader constraint violation ... com.google.auth.Credentials
    # so only copy the jars that are not on the worker classpath
    for jar in GoogleBigQueryJDBC42.jar \
               google-api-services-bigquery-v2-rev20221028-2.0.0.jar \
               google-cloud-bigquerystorage-2.26.0.jar \
               grpc-google-cloud-bigquerystorage-v1-2.26.0.jar \
               grpc-google-cloud-bigquerystorage-v1beta1-0.150.0.jar \
               grpc-google-cloud-bigquerystorage-v1beta2-0.150.0.jar \
               proto-google-cloud-bigquerystorage-v1-2.26.0.jar \
               proto-google-cloud-bigquerystorage-v1beta1-0.150.0.jar \
               proto-google-cloud-bigquerystorage-v1beta2-0.150.0.jar
    do
        cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/$jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/$jar
    done
else
    cp ../../connect/connect-jdbc-gcp-bigquery-source/GoogleBigQueryJDBC42/*.jar ../../confluent-hub/confluentinc-kafka-connect-jdbc/lib/
fi
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Creating JDBC GCP BigQuery Source connector"
playground connector create-or-update --connector jdbc-gcp-bigquery-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;ProjectId=$GCP_PROJECT;OAuthType=0;OAuthServiceAcctEmail=$SERVICE_ACCOUNT_EMAIL;OAuthPvtKeyPath=/tmp/keyfile.json;DefaultDataset=$DATASET;IgnoreTransactions=1;",
    "catalog.pattern": "$GCP_PROJECT",
    "schema.pattern": "$DATASET",
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

log "Verifying topic gcp-customers"
playground topic consume --topic gcp-customers --min-expected-messages 1 --timeout 60