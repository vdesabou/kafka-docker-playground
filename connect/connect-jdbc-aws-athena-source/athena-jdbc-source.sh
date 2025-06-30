#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

cd ../../connect/connect-jdbc-aws-athena-source
if [ ! -f ${PWD}/AthenaJDBC42-2.1.3.1002.jar ]
then
    wget -q https://downloads.athena.us-east-1.amazonaws.com/drivers/JDBC/SimbaAthenaJDBC-2.1.3.1002/AthenaJDBC42-2.1.3.1002.jar
fi
cd -

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "❌ either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
     exit 1
else
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
        log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        if [ -f $HOME/.aws/credentials ]
        then
            logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' ) 
        fi
    fi
    if [ -z "$AWS_REGION" ]
    then
        AWS_REGION=$(aws configure get region | tr '\r' '\n')
        if [ "$AWS_REGION" == "" ]
        then
            logerror "❌ either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
            exit 1
        fi
    fi
fi

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}
ATHENA_WORK_GROUP=pg${USER}jdbcathena
ATHENA_WORK_GROUP=${ATHENA_WORK_GROUP//[-._]/}

export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_ATHENA_S3_STAGING_DIR=s3://$AWS_BUCKET_NAME/athena
export AWS_ATHENA_WORK_GROUP=$ATHENA_WORK_GROUP

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Create table CUSTOMERS"
docker run -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -e AWS_ATHENA_S3_STAGING_DIR=$AWS_ATHENA_S3_STAGING_DIR -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION -e ATHENA_WORK_GROUP=$ATHENA_WORK_GROUP --rm -ti -v $(pwd):/home/athena zzl0/athenacli athenacli -e /home/athena/customers.sql

log "Creating JDBC AWS Athena source connector"
playground connector create-or-update --connector athena-jdbc-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:awsathena://AwsRegion=$AWS_DEFAULT_REGION;S3OutputLocation=$AWS_ATHENA_S3_STAGING_DIR",
    "connection.user": "$AWS_ACCESS_KEY_ID",
    "connection.password": "$AWS_SECRET_ACCESS_KEY",
    "_catalog.pattern": "AwsDataCatalog",
    "_schema.pattern": "default",
    "_table.whitelist": "customers",
    "query": "SELECT * FROM customers",
    "mode": "timestamp",
    "timestamp.column.name": "update_ts",
    "topic.prefix": "athena-customers",
    "validate.non.null":"false",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

# with custom dialect with "SELECT DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s')" it works

# athena-jdbc-source             ✅ RUNNING  0:🛑 FAILED[connect]          tasks: org.apache.kafka.connect.errors.ConnectException: java.sql.SQLDataException: [Simba][JDBC](10140) Error converting value to Timestamp.
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:521)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.poll(AbstractWorkerSourceTask.java:488)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.execute(AbstractWorkerSourceTask.java:360)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:229)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:284)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.run(AbstractWorkerSourceTask.java:80)
#         at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:237)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLDataException: [Simba][JDBC](10140) Error converting value to Timestamp.
#         at com.simba.athena.exceptions.ExceptionConverter.toSQLException(Unknown Source)
#         at com.simba.athena.utilities.conversion.TypeConverter.convertToTimestamp(Unknown Source)
#         at com.simba.athena.utilities.conversion.TypeConverter.toTimestamp(Unknown Source)
#         at com.simba.athena.jdbc.common.SForwardResultSet.getTimestamp(Unknown Source)
#         at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.currentTimeOnDB(GenericDatabaseDialect.java:565)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingTableQuerier.endTimestampValue(TimestampIncrementingTableQuerier.java:251)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.setQueryParametersTimestamp(TimestampIncrementingCriteria.java:174)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingCriteria.setQueryParameters(TimestampIncrementingCriteria.java:136)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingTableQuerier.executeQuery(TimestampIncrementingTableQuerier.java:211)
#         at io.confluent.connect.jdbc.source.TimestampTableQuerier.executeQuery(TimestampTableQuerier.java:119)
#         at io.confluent.connect.jdbc.source.TimestampIncrementingTableQuerier.maybeStartQuery(TimestampIncrementingTableQuerier.java:164)
#         at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:482)
#         ... 11 more

sleep 5

log "Verifying topic athena-customers"
playground topic consume --topic athena-customers --min-expected-messages 5 --timeout 60
