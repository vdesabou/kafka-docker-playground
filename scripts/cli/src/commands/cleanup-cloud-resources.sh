user="${args[--user]}"
force="${args[--force]}"

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

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    az logout
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
fi

maybe_set_azure_subscription

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

log "Cleanup AWS Kinesis streams"
for stream in $(aws kinesis list-streams --region $AWS_REGION | jq '.StreamNames[]' -r)
do
    if [[ $stream = *pg${user}* ]]
    then
        log "Removing AWS Kinesis stream $stream"
        check_if_skip "aws kinesis delete-stream --stream-name $stream --region $AWS_REGION"
    fi
done

log "Cleanup AWS Redshift clusters"
for cluster in $(aws redshift describe-clusters --region $AWS_REGION | jq '.Clusters[].ClusterIdentifier' -r)
do
    if [[ $cluster = pg${user}redshift* ]]
    then
        log "Delete AWS Redshift $cluster"
        check_if_skip "aws redshift delete-cluster --cluster-identifier $cluster --skip-final-cluster-snapshot --region $AWS_REGION"
        sleep 60
        log "Delete AWS security group sg$cluster"
        check_if_skip "aws ec2 delete-security-group --group-name sg$cluster --region $AWS_REGION"
    fi
done

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

# always exit with success
exit 0
