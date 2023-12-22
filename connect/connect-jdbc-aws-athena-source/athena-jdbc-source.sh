#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-aws-athena-source
if [ ! -f ${PWD}/AthenaJDBC42-2.1.1.1000.jar ]
then
     wget https://downloads.athena.us-east-1.amazonaws.com/drivers/JDBC/SimbaAthenaJDBC-2.1.1.1000/AthenaJDBC42-2.1.1.1000.jar
fi
cd -

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "ERROR: either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
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
            logerror "ERROR: either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
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

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Create table CUSTOMERS"
docker run -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -e AWS_ATHENA_S3_STAGING_DIR=$AWS_ATHENA_S3_STAGING_DIR -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION -e ATHENA_WORK_GROUP=$ATHENA_WORK_GROUP --rm -ti -v $(pwd):/home/athena zzl0/athenacli athenacli -e /home/athena/customers.sql

log "Creating JDBC AWS Athena source connector"
playground connector create-or-update --connector athena-jdbc-source << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:awsathena://athena.$AWS_DEFAULT_REGION.amazonaws.com:443;S3OutputLocation=$AWS_ATHENA_S3_STAGING_DIR;Workgroup=primary",
     "connection.user": "$AWS_ACCESS_KEY_ID",
     "connection.password": "$AWS_SECRET_ACCESS_KEY",
     "table.whitelist": "customers",
     "mode": "timestamp",
     "timestamp.column.name": "update_ts",
     "topic.prefix": "athena-",
     "validate.non.null":"false",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

sleep 5

log "Verifying topic athena-customers"
playground topic consume --topic athena-customers --min-expected-messages 5 --timeout 60
