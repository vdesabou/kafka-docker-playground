user="${args[--user]}"

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi

handle_aws_credentials

for stream in $(aws kinesis list-streams --region $AWS_REGION | jq '.StreamNames[]' -r)
do
    if [[ $stream = *pg*${user}* ]]
    then
        log "🔥 AWS Kinesis stream $stream"
    fi
done

for queue in $(aws sqs list-queues --region $AWS_REGION | jq '.QueueUrls[]' -r)
do
    if [[ $queue = *pg*${user}* ]]
    then
        log "🔥 AWS SQS queue $queue"
    fi
done

for function in $(aws lambda list-functions --region $AWS_REGION | jq '.Functions[].FunctionName' -r)
do
    if [[ $function = *pglambdafunction* ]] || [[ $function = *pg*${user}* ]]
    then
        log "🔥 AWS Lambda function $function"
    fi
done

for role in $(aws iam list-roles --region $AWS_REGION | jq '.Roles[].RoleName' -r)
do
    if [[ $role = *pglambdarole* ]] || [[ $role = *pg*${user}* ]]
    then
        log "🔥 AWS Lambda role $role"
    fi
done

for log_group in $(aws logs describe-log-groups --region $AWS_REGION | jq '.logGroups[].logGroupName' -r)
do
    if [[ $log_group = *myloggroup* ]] || [[ $log_group = *pg*${user}* ]]
    then
        log "🔥 AWS CloudWatch log group $log_group"
    fi
done

for cluster in $(aws redshift describe-clusters --region $AWS_REGION | jq '.Clusters[].ClusterIdentifier' -r)
do
    if [[ $cluster = pg*${user}redshift* ]] || [[ $cluster = pg*${user}jdbcredshift* ]]
    then
        log "🔥 AWS Redshift $cluster"
    fi
done

for dynamo_table in $(aws dynamodb list-tables --region $AWS_REGION | jq '.TableNames[]' -r)
do
    if [[ $dynamo_table = pg*${user}* ]]
    then
        log "🔥 AWS dynamodb table $dynamo_table"
    fi
done