user="${args[--user]}"
force="${args[--force]}"
# Convert the space delimited string to an array
eval "resources=(${args[--resource]})"

set +e
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi

function cleanup_aws () {
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

    log "Cleanup AWS Kinesis streams"
    for stream in $(aws kinesis list-streams --region $AWS_REGION | jq '.StreamNames[]' -r)
    do
        if [[ $stream = *pg${user}* ]]
        then
            log "Removing AWS Kinesis stream $stream"
            check_if_skip "aws kinesis delete-stream --stream-name $stream --region $AWS_REGION"
        fi
    done

    log "Cleanup AWS SQS queues"
    for queue in $(aws sqs list-queues --region $AWS_REGION | jq '.QueueUrls[]' -r)
    do
        if [[ $queue = *pg${user}* ]]
        then
            log "Removing AWS SQS queue $queue"
            check_if_skip "aws sqs delete-queue --queue-url ${queue}"
        fi
    done

    log "Cleanup AWS Lambda functions"
    for function in $(aws lambda list-functions --region $AWS_REGION | jq '.Functions[].FunctionName' -r)
    do
        if [[ $function = *pglambdafunction* ]] || [[ $function = *pg${user}* ]]
        then
            log "Removing AWS Lambda function $function"
            check_if_skip "aws lambda delete-function --function-name ${function}"
        fi
    done

    log "Cleanup AWS Lambda IAM roles"
    for role in $(aws iam list-roles --region $AWS_REGION | jq '.Roles[].RoleName' -r)
    do
        if [[ $role = *pglambdarole* ]] || [[ $role = *pg${user}* ]]
        then
            log "Removing AWS Lambda role $role"
            check_if_skip "aws iam delete-role --role-name ${role}"
        fi
    done

    log "Cleanup AWS CloudWatch log group"
    for log_group in $(aws logs describe-log-groups --region $AWS_REGION | jq '.logGroups[].logGroupName' -r)
    do
        if [[ $log_group = *myloggroup* ]] || [[ $log_group = *pg${user}* ]]
        then
            for log_stream in $(aws logs describe-log-streams --log-group-name $log_group --region $AWS_REGION | jq '.logStreams[].logStreamName' -r)
            do
                log "Removing AWS CloudWatch log stream $log_stream for log group $log_group"
                check_if_skip "aws logs delete-log-stream --log-group-name ${log_group} --log-stream-name ${log_stream}"
            done

            log "Removing AWS CloudWatch log group $log_group"
            check_if_skip "aws logs delete-log-group --log-group-name ${log_group}"
        fi
    done

    log "Cleanup AWS Redshift clusters"
    for cluster in $(aws redshift describe-clusters --region $AWS_REGION | jq '.Clusters[].ClusterIdentifier' -r)
    do
        if [[ $cluster = pg${user}redshift* ]] || [[ $cluster = pg${user}jdbcredshift* ]]
        then
            log "Delete AWS Redshift $cluster"
            check_if_skip "aws redshift delete-cluster --cluster-identifier $cluster --skip-final-cluster-snapshot --region $AWS_REGION"
            sleep 60
            log "Delete AWS security group sg$cluster"
            check_if_skip "aws ec2 delete-security-group --group-name sg$cluster --region $AWS_REGION"
        fi
    done

    log "Cleanup AWS DynamoDB tables"
    for dynamo_table in $(aws dynamodb list-tables --region $AWS_REGION | jq '.TableNames[].TableName' -r)
    do
        if [[ $dynamo_table = *pg${user}* ]]
        then
            log "Removing AWS dynamodb table $dynamo_table"
            check_if_skip "aws dynamodb delete-table --table-name ${dynamo_table}"
        fi
    done
}

function cleanup_azure () {
    if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
    then
        az logout
        az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
    fi

    login_and_maybe_set_azure_subscription

    log "Cleanup Azure Resource groups"
    for group in $(az group list --query '[].name' --output tsv)
    do
    if [[ $group = pg${user}* ]]
    then
        if [ ! -z "$GITHUB_RUN_NUMBER" ]
        then
        job=$(echo $GITHUB_RUN_NUMBER | cut -d "." -f 1)
        if [[ $group = pg$user$job* ]]
        then
            log "Skipping current github actions $job"
            continue
        fi
        fi
        log "Deleting Azure resource group $group"
        check_if_skip "az group delete --name $group --yes --no-wait"
    fi
    done
}

function cleanup_gcp () {
    log "Cleanup GCP GCS buckets"
    GCP_KEYFILE="$tmp_dir/keyfile.json"
    echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    docker rm -f gcloud-config-cleanup-resources > /dev/null 2>&1
    docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json > /dev/null 2>&1

    for bucket in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil ls)
    do
        if [[ $bucket = *kafkadockerplaygroundbucket${user}* ]]
        then
            log "Removing GCS bucket $bucket"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil -m rm -r $bucket"
        fi
    done

    log "Cleanup GCP BQ datasets"
    for dataset in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" ls)
    do
        if [[ $dataset = *pg${user}* ]]
        then
            log "Remove GCP BQ dataset $dataset"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id \"$GCP_PROJECT\" rm -r -f -d \"$dataset\""
        fi
    done

    GCP_SPANNER_INSTANCE="spanner-instance-$USER"
    GCP_SPANNER_DATABASE="spanner-db-$USER"
    log "Deleting Spanner database $GCP_SPANNER_DATABASE"
    docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner databases delete $GCP_SPANNER_DATABASE --instance $GCP_SPANNER_INSTANCE --project $GCP_PROJECT << EOF > /dev/null 2>&1
Y
EOF
    log "Deleting Spanner instance $GCP_SPANNER_INSTANCE"
    docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner instances delete $GCP_SPANNER_INSTANCE --project $GCP_PROJECT  << EOF > /dev/null 2>&1
Y
EOF

    GCP_BIGTABLE_INSTANCE="bigtable-$USER"
    log "Delete BigTable table kafka_big_query_stats"
    docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $GCP_BIGTABLE_INSTANCE deletetable kafka_big_query_stats

    log "Deleting BigTable instance $GCP_BIGTABLE_INSTANCE"
    docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud bigtable instances delete $GCP_BIGTABLE_INSTANCE --project $GCP_PROJECT << EOF > /dev/null 2>&1
Y
EOF
}

function cleanup_ccloud () {
    cleanup_confluent_cloud_resources

    if [ ! -z "$AWS_DATABRICKS_CLUSTER_NAME" ]
    then
        log "AWS_DATABRICKS_CLUSTER_NAME environment variable is set, forcing the cluster $AWS_DATABRICKS_CLUSTER_NAME to be used !"
        export CLUSTER_NAME=$AWS_DATABRICKS_CLUSTER_NAME
        export CLUSTER_REGION=$AWS_DATABRICKS_CLUSTER_REGION
        export CLUSTER_CLOUD=$AWS_DATABRICKS_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AWS_DATABRICKS_CLUSTER_CREDS

        cleanup_confluent_cloud_resources
    fi

    if [ ! -z "$AWS_CLUSTER_NAME" ]
    then
        log "AWS_CLUSTER_NAME environment variable is set, forcing the cluster $AWS_CLUSTER_NAME to be used !"
        export CLUSTER_NAME=$AWS_CLUSTER_NAME
        export CLUSTER_REGION=$AWS_CLUSTER_REGION
        export CLUSTER_CLOUD=$AWS_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AWS_CLUSTER_CREDS

        cleanup_confluent_cloud_resources
    fi

    if [ ! -z "$GCP_CLUSTER_NAME" ]
    then
        log "GCP_CLUSTER_NAME environment variable is set, forcing the cluster $GCP_CLUSTER_NAME to be used !"
        export CLUSTER_NAME=$GCP_CLUSTER_NAME
        export CLUSTER_REGION=$GCP_CLUSTER_REGION
        export CLUSTER_CLOUD=$GCP_CLUSTER_CLOUD
        export CLUSTER_CREDS=$GCP_CLUSTER_CREDS

        cleanup_confluent_cloud_resources
    fi

    if [ ! -z "$AZURE_CLUSTER_NAME" ]
    then
        log "AZURE_CLUSTER_NAME environment variable is set, forcing the cluster $AZURE_CLUSTER_NAME to be used !"
        export CLUSTER_NAME=$AZURE_CLUSTER_NAME
        export CLUSTER_REGION=$AZURE_CLUSTER_REGION
        export CLUSTER_CLOUD=$AZURE_CLUSTER_CLOUD
        export CLUSTER_CREDS=$AZURE_CLUSTER_CREDS

        cleanup_confluent_cloud_resources
    fi
}

function cleanup_salesforce () {
    
    SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}
    if [ ! -z $SALESFORCE_USERNAME ]
    then
        log "Cleanup Salesforce Leads on account with $SALESFORCE_USERNAME"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\" && sfdx data:query --target-org \"$SALESFORCE_USERNAME\" -q \"SELECT Id FROM Lead\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$SALESFORCE_USERNAME\" -s Lead -f /tmp/out.csv"

        log "Cleanup Salesforce Contacts on account with $SALESFORCE_USERNAME"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SALESFORCE_SECURITY_TOKEN\" && sfdx data:query --target-org \"$SALESFORCE_USERNAME\" -q \"SELECT Id FROM Contact\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$SALESFORCE_USERNAME\" -s Contact -f /tmp/out.csv"

        log "Cleanup PushTopics on account with $SALESFORCE_USERNAME"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic];
Database.delete(pts);
EOF
    fi

    SALESFORCE_INSTANCE_ACCOUNT2=${SALESFORCE_INSTANCE_ACCOUNT2:-"https://login.salesforce.com"}
    if [ ! -z $SALESFORCE_USERNAME_ACCOUNT2 ]
    then
        log "Cleanup Salesforce Leads on account with $SALESFORCE_USERNAME_ACCOUNT2"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\" && sfdx data:query --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -q \"SELECT Id FROM Lead\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Lead -f /tmp/out.csv"

        log "Cleanup Salesforce Contacts on account with $SALESFORCE_USERNAME_ACCOUNT2"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME_ACCOUNT2\" -p \"$SALESFORCE_PASSWORD_ACCOUNT2\" -r \"$SALESFORCE_INSTANCE_ACCOUNT2\" -s \"$SALESFORCE_SECURITY_TOKEN_ACCOUNT2\" && sfdx data:query --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -q \"SELECT Id FROM Contact\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\" -s Contact -f /tmp/out.csv"

        log "Cleanup PushTopics on account with $SALESFORCE_USERNAME_ACCOUNT2"
        docker run -i --rm vdesabou/sfdx-cli:latest sh -c "sfdx apex run --target-org \"$SALESFORCE_USERNAME_ACCOUNT2\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic];
Database.delete(pts);
EOF
    fi
}

for resource in "${resources[@]}"
do
    case "${resource}" in

        "aws")
            cleanup_aws
        ;;
        "gcp")
            cleanup_gcp
        ;;
        "azure")
            cleanup_azure
        ;;
        "ccloud")
            cleanup_ccloud
        ;;
        "salesforce")
            cleanup_salesforce
        ;;
        *)
            logerror "default (none of above)"
        ;;
    esac
done

# always exit with success
exit 0
