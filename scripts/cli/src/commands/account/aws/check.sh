GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

if ! type -P aws > /dev/null 2>&1 && ! docker info > /dev/null 2>&1
then
    logerror "❌ neither the aws CLI nor a running docker (for the amazon/aws-cli image)"
    exit 1
fi

aws_account_resolve_credentials
if [ -z "$aws_key_id" ] || [ -z "$aws_secret" ]
then
    logerror "❌ no AWS keys: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are not set and $HOME/.aws/credentials has none (all the AWS examples need them)"
    logerror "👉 playground account aws setup"
    exit 1
fi

# 1. the keys
log "🔑 keys ${aws_key_id:0:8}… from $aws_key_source"
if [ -n "$aws_token" ] || [[ "$aws_key_id" == ASIA* ]]
then
    logwarn "⚠️ temporary credentials (session token): fine for the self-managed examples, refused for ccloud/fm-aws-* and custom connectors"
fi
if [ -z "$aws_region" ]
then
    logerror "❌ no region: AWS_REGION is not set and your aws CLI has no default region"
    logerror "👉 playground account aws setup --region <region>"
    exit 1
fi
if ! identity=$(aws_account_cli sts get-caller-identity 2>&1)
then
    code=$(aws_account_error_code "$identity")
    logerror "❌ AWS rejected the keys: ${code:-$(echo "$identity" | head -1)}"
    cause=$(aws_account_explain_error "$code")
    [ -n "$cause" ] && logerror "   $cause"
    exit 1
fi
arn=$(echo "$identity" | jq -r '.Arn')
account_id=$(echo "$identity" | jq -r '.Account')
log "✅ keys work: $arn (account $account_id)"
if [[ "$arn" == *":root" ]]
then
    logwarn "⚠️ these are the keys of the root user: use an IAM user"
fi

# 2. the region
if out=$(aws_account_cli ec2 describe-regions --region-names "$aws_region" --query 'Regions[0].RegionName' --output text 2>&1)
then
    echo -e "✅ ${GREEN}Region${NC} $aws_region"
else
    code=$(aws_account_error_code "$out")
    if [[ "$code" == "InvalidParameterValue" ]] || [[ "$code" == "EndpointConnectionError" ]]
    then
        echo -e "❌ ${RED}Region${NC} $aws_region is not a valid region        👉 playground account aws setup --region <region>"
        exit 1
    fi
    echo -e "✅ ${GREEN}Region${NC} $aws_region (not verified: ${code:-ec2 describe-regions failed})"
fi

# 3. one read-only call per service: name|examples|command
nb_failed=0
function aws_check_probe () {
    name="$1"
    examples="$2"
    shift 2
    if out=$(aws_account_cli "$@" 2>&1)
    then
        echo -e "✅ ${GREEN}$name${NC}"
        return 0
    fi
    code=$(aws_account_error_code "$out")
    cause=$(aws_account_explain_error "$code")
    echo -e "❌ ${RED}$name${NC}: ${code:-$(echo "$out" | grep -v '^$' | head -1 | cut -c1-120)}${cause:+ ($cause)}"
    echo "      needed by: $examples"
    nb_failed=$((nb_failed + 1))
    return 1
}
aws_check_probe "S3" "s3 sink and source, athena, filepulse s3, snowflake iceberg external volume" s3api list-buckets --max-items 1 || true
aws_check_probe "Kinesis" "kinesis source" kinesis list-streams --max-items 1 || true
aws_check_probe "SQS" "sqs source" sqs list-queues --max-results 1 || true
aws_check_probe "DynamoDB" "dynamodb sink, dynamodb cdc source" dynamodb list-tables --max-items 1 || true
aws_check_probe "Lambda" "lambda sink" lambda list-functions --max-items 1 || true
aws_check_probe "IAM roles" "lambda sink (creates the role of its function), snowflake iceberg external volume" iam list-roles --max-items 1 || true
aws_check_probe "CloudWatch Logs" "cloudwatch logs source" logs describe-log-groups --limit 1 || true
aws_check_probe "CloudWatch Metrics" "cloudwatch metrics sink" cloudwatch list-metrics --namespace AWS/Usage --max-items 1 || true
aws_check_probe "Redshift" "redshift sink, jdbc redshift sink and source" redshift describe-clusters --max-records 20 || true
aws_check_probe "Athena" "jdbc athena source" athena list-work-groups --max-results 1 || true

# 4. the bucket of your examples (pgbucket<user>): a bucket of that name in another account would break them
bucket="pg-bucket-${USER}"
bucket="${bucket//[-.]/}"
if out=$(aws_account_cli s3api get-bucket-location --bucket "$bucket" 2>&1)
then
    location=$(echo "$out" | jq -r '.LocationConstraint // "us-east-1"')
    [ "$location" == "null" ] && location="us-east-1"
    if [ "$location" == "$aws_region" ]
    then
        echo -e "✅ ${GREEN}Bucket${NC} $bucket exists in $aws_region"
    else
        echo -e "⚠️ ${YELLOW}Bucket${NC} $bucket exists in $location, not in $aws_region: the s3 examples expect it in AWS_REGION        👉 aws s3 rb s3://$bucket --force"
    fi
else
    code=$(aws_account_error_code "$out")
    case "$code" in
        NoSuchBucket) echo -e "✅ ${GREEN}Bucket${NC} $bucket does not exist yet (the s3 examples create it)" ;;
        AccessDenied|AllAccessDisabled) echo -e "❌ ${RED}Bucket${NC} $bucket belongs to another AWS account: the s3 examples can't create it        👉 run them with another USER"; nb_failed=$((nb_failed + 1)) ;;
        *) echo -e "⚠️ ${YELLOW}Bucket${NC} $bucket: ${code:-unknown}" ;;
    esac
fi

# 5. the assume-role variants
profile="$(get_active_secret_profile)"
role_arn="$(secret_get AWS_STS_ROLE_ARN "$profile" 2> /dev/null || true)"
second_key_id="$(secret_get AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID "$profile" 2> /dev/null || true)"
second_secret="$(secret_get AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY "$profile" 2> /dev/null || true)"
if [ -z "$role_arn" ]
then
    echo -e "ℹ️  AWS_STS_ROLE_ARN is not set: only the assume-role variants need it        👉 playground account aws setup --assume-role"
elif [[ ! "$role_arn" =~ ^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+ ]]
then
    echo -e "❌ ${RED}AWS_STS_ROLE_ARN${NC} $role_arn is not a role ARN (arn:aws:iam::<account>:role/<name>)"
    nb_failed=$((nb_failed + 1))
elif [ -z "$second_key_id" ] || [ -z "$second_secret" ]
then
    echo -e "❌ ${RED}Assume role${NC}: AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID / _SECRET_ACCESS_KEY are not set        👉 playground account aws setup --assume-role"
    nb_failed=$((nb_failed + 1))
else
    if out=$(aws_key_id="$second_key_id" aws_secret="$second_secret" aws_token="" aws_account_cli sts assume-role --role-arn "$role_arn" --role-session-name pg-check --external-id 123 --duration-seconds 900 2>&1)
    then
        echo -e "✅ ${GREEN}Assume role${NC} $role_arn with the second account keys and external id 123 (like the assume-role variants)"
    else
        code=$(aws_account_error_code "$out")
        echo -e "❌ ${RED}Assume role${NC} $role_arn: ${code:-failed}"
        if [[ "$code" == "AccessDenied" ]]
        then
            echo "      the trust policy of the role must name the principal of the second account keys, with sts:ExternalId 123"
        else
            cause=$(aws_account_explain_error "$code")
            [ -n "$cause" ] && echo "      second account keys: $cause"
        fi
        echo "      needed by: the *assuming-iam-role* variants of the s3, dynamodb, kinesis, sqs, lambda, cloudwatch, redshift examples"
        nb_failed=$((nb_failed + 1))
    fi
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail"
else
    log "🎉 the AWS credentials are ready for the AWS examples"
fi
