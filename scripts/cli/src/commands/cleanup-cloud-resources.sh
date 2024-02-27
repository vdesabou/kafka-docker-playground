user="${args[--user]}"
force="${args[--force]}"

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    az logout
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
fi

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
set +e
docker rm -f gcloud-config-cleanup-resources > /dev/null 2>&1
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

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

# log "Cleanup AWS S3 buckets"
# for bucket in $(aws s3api list-buckets --region $AWS_REGION | jq .Buckets[].Name -r)
# do
#     if [[ $bucket = *pgbucket${user}* ]]
#     then
#         set +e
#         log "Removing AWS bucket $bucket"
#         if [[ ! -n "$force" ]]
#         then
#             check_if_continue
#         fi
#         aws s3 rb s3://$bucket --force --region $AWS_REGION
#         set -e
#     fi
# done

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
        set +e
        log "Delete AWS Redshift $cluster"
        check_if_skip "aws redshift delete-cluster --cluster-identifier $cluster --skip-final-cluster-snapshot --region $AWS_REGION"
        sleep 60
        log "Delete AWS security group sg$cluster"
        check_if_skip "aws ec2 delete-security-group --group-name sg$cluster --region $AWS_REGION"
        set -e
    fi
done

set +e 

bootstrap_ccloud_environment

# for row in $(confluent api-key list --output json | jq -r '.[] | @base64'); do
#     _jq() {
#     echo ${row} | base64 --decode | jq -r ${1}
#     }
    
#     key=$(echo $(_jq '.key'))
#     resource_type=$(echo $(_jq '.resource_type'))

#     if [[ $resource_type = cloud ]] && [[ "$key" != "$CLOUD_API_KEY" ]]
#     then
#       log "deleting cloud api key $key"
#       confluent api-key delete $key --force
#     fi
# done

for row in $(confluent connect cluster list --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
    }
    
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    log "deleting connector $id ($name)"
    check_if_skip "confluent connect cluster delete $id --force"
done

for row in $(confluent environment list --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
    }
    
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    if [[ $name = pg-${user}-sa-* ]]
    then
        log "deleting environment $id ($name)"
        check_if_skip "confluent environment delete $id --force"
    fi
done

for topic in $(confluent kafka topic list | awk '{if(NR>2) print $1}')
do
    log "delete topic $topic"
    check_if_skip "confluent kafka topic delete \"$topic\" --force"
done

for subject in $(curl -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]')
do
    log "permanently delete subject $subject"
    check_if_skip "curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject\" && curl --request DELETE -u \"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO\" \"$SCHEMA_REGISTRY_URL/subjects/$subject?permanent=true\""
done

for row in $(confluent iam service-account list --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 --decode | jq -r ${1}
    }
    
    description=$(echo $(_jq '.description'))
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    log "deleting service-account $id ($description)"
    check_if_skip "confluent iam service-account delete $id --force"
done


# always exit with success
exit 0
