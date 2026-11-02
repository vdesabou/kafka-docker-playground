user="${args[--user]}"
force="${args[--force]}"
# Convert the space delimited string to an array
eval "resources=(${args[--resource]})"
recorded_topics_only="${args[--recorded-topics-only]}"
# read by check_if_skip and confirm_deletion: every deletion is shown, none is run
dry_run="${args[--dry-run]}"
if [[ -n "$dry_run" ]] && [[ -n "$recorded_topics_only" ]]
then
    # bashly only checks a conflict against the flags already parsed: also refused here, whatever the order
    logerror "❌ --dry-run can't be used with --recorded-topics-only"
    exit 1
fi
if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run: listing what would be deleted, nothing is deleted"
fi

if [[ -n "$recorded_topics_only" ]]
then
    cleanup_ccloud_recorded_topics
    exit 0
fi

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
# examples strip - . _ from the user in the names of their cloud resources (${USER//[-._]/}), some also lowercase it
user_lower=$(tr '[:upper:]' '[:lower:]' <<< "$user")
user_normalized=$(tr '[:upper:]' '[:lower:]' <<< "${user//[-._]/}")

# true when the resource name contains pg<anything><user>, with the user as is or normalized like the examples do
function name_has_user () {
    local name
    name=$(tr '[:upper:]' '[:lower:]' <<< "$1")
    [[ $name = *pg*${user_lower}* ]] || [[ $name = *pg*${user_normalized}* ]]
}

# true when the deletion described by $1 can go on: always with --force or in CI, otherwise when the user answers y
function confirm_deletion () {
    if [[ -n "$dry_run" ]]
    then
        log "🔎 dry-run, would ask: $1"
        return 1
    fi
    if [[ -n "$force" ]] || [ -n "$GITHUB_RUN_NUMBER" ]
    then
        return 0
    fi
    local reply
    while true
    do
        read -p "$1 (y/n) " reply
        case "$reply" in
            y|Y ) return 0;;
            n|N ) log "Skipping..."; return 1;;
            * ) logwarn "invalid response <$reply>! Please enter y or n.";;
        esac
    done
}

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
        if name_has_user "$stream"
        then
            log "Removing AWS Kinesis stream $stream"
            check_if_skip "aws kinesis delete-stream --stream-name $stream --region $AWS_REGION"
        fi
    done

    log "Cleanup AWS SQS queues"
    for queue in $(aws sqs list-queues --region $AWS_REGION | jq '.QueueUrls[]' -r)
    do
        if name_has_user "$queue"
        then
            log "Removing AWS SQS queue $queue"
            check_if_skip "aws sqs delete-queue --queue-url ${queue}"
        fi
    done

    log "Cleanup AWS Lambda functions"
    for function in $(aws lambda list-functions --region $AWS_REGION | jq '.Functions[].FunctionName' -r)
    do
        if name_has_user "$function"
        then
            log "Removing AWS Lambda function $function"
            check_if_skip "aws lambda delete-function --function-name ${function}"
        fi
    done

    log "Cleanup AWS Lambda IAM roles"
    for role in $(aws iam list-roles --region $AWS_REGION | jq '.Roles[].RoleName' -r)
    do
        if name_has_user "$role"
        then
            log "Removing AWS Lambda role $role"
            if confirm_deletion "Delete AWS IAM role $role?"
            then
                # a role with attached (AWSLambdaBasicExecutionRole…) or inline policies can't be deleted (DeleteConflict)
                for policy in $(aws iam list-attached-role-policies --role-name ${role} | jq -r '.AttachedPolicies[].PolicyArn')
                do
                    aws iam detach-role-policy --role-name ${role} --policy-arn $policy
                done
                for policy in $(aws iam list-role-policies --role-name ${role} | jq -r '.PolicyNames[]')
                do
                    aws iam delete-role-policy --role-name ${role} --policy-name $policy
                done
                aws iam delete-role --role-name ${role}
            fi
        fi
    done

    log "Cleanup AWS CloudWatch log group"
    for log_group in $(aws logs describe-log-groups --region $AWS_REGION | jq '.logGroups[].logGroupName' -r)
    do
        if name_has_user "$log_group"
        then
            # for log_stream in $(aws logs describe-log-streams --log-group-name $log_group --region $AWS_REGION | jq '.logStreams[].logStreamName' -r)
            # do
            #     log "Removing AWS CloudWatch log stream $log_stream for log group $log_group"
            #     check_if_skip "aws logs delete-log-stream --log-group-name ${log_group} --log-stream-name \"${log_stream}\""
            # done

            log "Removing AWS CloudWatch log group $log_group"
            check_if_skip "aws logs delete-log-group --log-group-name ${log_group}"
        fi
    done

    log "Cleanup AWS Redshift clusters"
    for cluster in $(aws redshift describe-clusters --region $AWS_REGION | jq '.Clusters[].ClusterIdentifier' -r)
    do
        if [[ $cluster = pg*${user_lower}redshift* ]] || [[ $cluster = pg*${user_lower}jdbcredshift* ]] || [[ $cluster = pg*${user_normalized}redshift* ]] || [[ $cluster = pg*${user_normalized}jdbcredshift* ]]
        then
            log "Delete AWS Redshift $cluster"
            if confirm_deletion "Delete AWS Redshift cluster $cluster and its security group sg$cluster?"
            then
                aws redshift delete-cluster --cluster-identifier $cluster --skip-final-cluster-snapshot --region $AWS_REGION
                # the security group is in use until the cluster is gone, which takes several minutes
                log "Waiting for AWS Redshift $cluster to be deleted"
                aws redshift wait cluster-deleted --cluster-identifier $cluster --region $AWS_REGION
                log "Delete AWS security group sg$cluster"
                aws ec2 delete-security-group --group-name sg$cluster --region $AWS_REGION
            fi
        fi
    done

    log "Cleanup AWS DynamoDB tables"
    for dynamo_table in $(aws dynamodb list-tables --region $AWS_REGION | jq '.TableNames[]' -r)
    do
        if name_has_user "$dynamo_table"
        then
            log "Removing AWS dynamodb table $dynamo_table"
            check_if_skip "aws dynamodb delete-table --table-name ${dynamo_table}"
        fi
    done
}

function cleanup_azure () {
    login_and_maybe_set_azure_subscription

    log "Cleanup Azure Resource groups"
    for group in $(az group list --query '[].name' --output tsv)
    do
    if name_has_user "$group"
    then
        if [ ! -z "$GITHUB_RUN_NUMBER" ]
        then
        job=$(echo $GITHUB_RUN_NUMBER | cut -d "." -f 1)
        # names are pg<user><type><run number>…, e.g. pg${USER}bk${GITHUB_RUN_NUMBER}
        if [[ $group =~ ^pg(${user_lower}|${user_normalized})[a-z]*${job} ]]
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
    GCP_KEYFILE="$tmp_dir/keyfile.json"
    if [ -z "$GCP_KEYFILE_CONTENT" ] || [ -z "$GCP_PROJECT" ]
    then
        logwarn "⏭️ GCP_KEYFILE_CONTENT or GCP_PROJECT is not set, skipping GCP cleanup"
        return
    fi
    echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    docker rm -f gcloud-config-cleanup-resources > /dev/null 2>&1
    if ! docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json > /dev/null 2>&1
    then
        logerror "❌ could not authenticate to GCP project $GCP_PROJECT with GCP_KEYFILE_CONTENT, skipping GCP cleanup"
        docker rm -f gcloud-config-cleanup-resources > /dev/null 2>&1
        return
    fi

    log "Cleanup GCP GCS buckets"
    for bucket in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil ls)
    do
        if [[ $bucket = *kafkadockerplaygroundbucket${user_lower}* ]] || [[ $bucket = *kafkadockerplaygroundbucket${user_normalized}* ]]
        then
            log "Removing GCS bucket $bucket"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil -m rm -r $bucket"
        fi
    done

    log "Cleanup GCP BQ datasets"
    for dataset in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" ls)
    do
        if name_has_user "$dataset"
        then
            log "Remove GCP BQ dataset $dataset"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id \"$GCP_PROJECT\" rm -r -f -d \"$dataset\""
        fi
    done

    log "Cleanup Spanner instances"
    for spanner_instance in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner instances list --project $GCP_PROJECT --format="value(NAME)")
    do
        if name_has_user "$spanner_instance"
        then

#             for spanner_db in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner databases list --project $GCP_PROJECT --instance $spanner_instance --format="value(NAME)")
#             do
#                 log "Remove Spanner database $spanner_db"
#                 docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner databases delete $spanner_db --instance $spanner_instance --project $GCP_PROJECT << EOF
# Y
# EOF
#             done

            for spanner_backup in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner backups list --project $GCP_PROJECT --instance $spanner_instance --format="value(NAME)")
            do
                log "Remove Spanner backup $spanner_backup"
                check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner backups delete $spanner_backup --instance $spanner_instance --project $GCP_PROJECT --quiet"
            done

            log "Remove Spanner instance $spanner_instance"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud spanner instances delete $spanner_instance --project $GCP_PROJECT --quiet"
        fi
    done

    log "Cleanup BigTable instances"
    for bigtable_instance in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud bigtable instances list --project $GCP_PROJECT --format="value(NAME)")
    do
        if name_has_user "$bigtable_instance"
        then
            log "Remove BigTable instance $bigtable_instance"
            check_if_skip "docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud bigtable instances delete $bigtable_instance --project $GCP_PROJECT --quiet"
        fi
    done

    docker rm -f gcloud-config-cleanup-resources > /dev/null 2>&1
}

function cleanup_ccloud () {
    if [[ -n "$dry_run" ]] && [ -z "$CLUSTER_NAME" ] && [ -z "$(playground state get ccloud.CLUSTER_NAME)" ]
    then
        # bootstrap_ccloud_environment would create a cluster: not in a dry-run
        logwarn "⏭️ dry-run: no Confluent Cloud cluster known (CLUSTER_NAME or a previous ccloud run), skipping Confluent Cloud"
        return
    fi
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

# Run sfdx commands against one org in a one-shot sfdx-cli container, logged in with the
# OAuth JWT bearer flow - the same External Client App, certificate and user the Salesforce
# connectors use. The connector keystore is mounted read-only and converted to the PEM key
# sfdx needs with the image's own openssl, so the key never lands on the host.
#
# Replaces `sfdx sfpowerkit:auth:login` (username + password + security token), whose SOAP
# login() Salesforce blocks by default on orgs created Summer '26 or later and retires with
# Summer '27. stdin is passed through, for `sfdx apex run` fed from a heredoc.
function salesforce_sfdx_run_as () {
    local username="$1" consumer_key="$2" instance="$3" commands="$4"

    docker run -i --rm -v "$SALESFORCE_JWT_KEYSTORE:/tmp/salesforce-confluent.keystore.jks:ro" vdesabou/sfdx-cli:latest sh -c "openssl pkcs12 -in /tmp/salesforce-confluent.keystore.jks -nocerts -nodes -passin pass:confluent -out /tmp/salesforce-confluent.key && sfdx auth:jwt:grant --username \"$username\" --client-id \"$consumer_key\" --jwt-key-file /tmp/salesforce-confluent.key --instance-url \"$instance\" && $commands"
}

function cleanup_salesforce_org () {
    local username="$1" consumer_key="$2" instance="$3"

    if [ -z "$consumer_key" ]
    then
        logwarn "⚠️ no JWT consumer key set for $username, skipping Salesforce cleanup for this account"
        return
    fi

    # the Salesforce accounts of the playground are dedicated test orgs: every Lead, Contact and PushTopic is deleted
    if ! confirm_deletion "Delete every Lead, Contact and PushTopic of Salesforce account $username?"
    then
        return
    fi

    log "Cleanup Salesforce Leads on account with $username"
    salesforce_sfdx_run_as "$username" "$consumer_key" "$instance" "sfdx data:query --target-org \"$username\" -q \"SELECT Id FROM Lead\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$username\" -s Lead -f /tmp/out.csv"

    log "Cleanup Salesforce Contacts on account with $username"
    salesforce_sfdx_run_as "$username" "$consumer_key" "$instance" "sfdx data:query --target-org \"$username\" -q \"SELECT Id FROM Contact\" --result-format csv > /tmp/out.csv && sfdx force:data:bulk:delete --target-org \"$username\" -s Contact -f /tmp/out.csv"

    log "Cleanup PushTopics on account with $username"
    salesforce_sfdx_run_as "$username" "$consumer_key" "$instance" "sfdx apex run --target-org \"$username\"" << EOF
List<PushTopic> pts = [SELECT Id FROM PushTopic];
Database.delete(pts);
EOF
}

function cleanup_salesforce () {
    local keystore_dir=""

    if [ -z "$SALESFORCE_USERNAME" ] && [ -z "$SALESFORCE_USERNAME_ACCOUNT2" ]
    then
        return
    fi

    # Same keystore every Salesforce example mounts into connect for the JWT_BEARER grant.
    keystore_dir=$(mktemp -d)
    (cd "$keystore_dir" && get_3rdparty_file "salesforce-confluent.keystore.jks")
    SALESFORCE_JWT_KEYSTORE="$keystore_dir/salesforce-confluent.keystore.jks"
    if [ ! -f "$SALESFORCE_JWT_KEYSTORE" ]
    then
        logerror "❌ could not fetch salesforce-confluent.keystore.jks, skipping Salesforce cleanup"
        return
    fi

    if [ ! -z "$SALESFORCE_USERNAME" ]
    then
        cleanup_salesforce_org "$SALESFORCE_USERNAME" "$SALESFORCE_CONSUMER_KEY_WITH_JWT" "${SALESFORCE_INSTANCE:-https://login.salesforce.com}"
    fi

    if [ ! -z "$SALESFORCE_USERNAME_ACCOUNT2" ]
    then
        cleanup_salesforce_org "$SALESFORCE_USERNAME_ACCOUNT2" "$SALESFORCE_CONSUMER_KEY_WITH_JWT_ACCOUNT2" "${SALESFORCE_INSTANCE_ACCOUNT2:-https://login.salesforce.com}"
    fi

    rm -rf "$keystore_dir"
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
