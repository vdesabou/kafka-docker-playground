aws_profile="${args[--profile]}"
region_arg="${args[--region]}"
assume_role="${args[--assume-role]}"
assume_role_profile="${args[--assume-role-profile]}"
dry_run="${args[--dry-run]}"
no_store="${args[--no-store]}"

if ! type -P aws > /dev/null 2>&1 && ! docker info > /dev/null 2>&1
then
    logerror "❌ neither the aws CLI nor a running docker (for the amazon/aws-cli image)"
    exit 1
fi
aws_bin="$(type -P aws 2> /dev/null || true)"
function aws_setup_profile_value () {
    if [ -z "$aws_bin" ]
    then
        logerror "❌ --profile needs the aws CLI installed"
        exit 1
    fi
    env -u AWS_PROFILE "$aws_bin" configure get "$1" --profile "$2" 2> /dev/null | tr -d '\r' || true
}

# 1. the keys and the region
if [[ -n "$aws_profile" ]]
then
    aws_key_id=$(aws_setup_profile_value aws_access_key_id "$aws_profile")
    aws_secret=$(aws_setup_profile_value aws_secret_access_key "$aws_profile")
    aws_token=$(aws_setup_profile_value aws_session_token "$aws_profile")
    aws_region=$(aws_setup_profile_value region "$aws_profile")
    aws_key_source="profile $aws_profile of your aws CLI"
    if [ -z "$aws_key_id" ] || [ -z "$aws_secret" ]
    then
        logerror "❌ profile $aws_profile has no aws_access_key_id / aws_secret_access_key (an SSO profile? its keys are temporary: create an IAM user access key instead)"
        exit 1
    fi
else
    aws_account_resolve_credentials
    if [ -z "$aws_key_id" ] || [ -z "$aws_secret" ]
    then
        logerror "❌ no AWS keys found: pass --profile, export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, or create ~/.aws/credentials (aws configure)"
        exit 1
    fi
fi
if [[ -n "$region_arg" ]]
then
    aws_region="$region_arg"
fi
if [ -z "$aws_region" ]
then
    logerror "❌ no region: pass --region (for the fully managed examples, a region Confluent Cloud supports)"
    exit 1
fi
log "🔑 keys ${aws_key_id:0:8}… from $aws_key_source, region $aws_region"
if [ -n "$aws_token" ] || [[ "$aws_key_id" == ASIA* ]]
then
    logerror "❌ these are temporary credentials (session token): the fully managed connectors refuse them, and they expire"
    logerror "   use the access key of an IAM user (IAM > Users > Security credentials > Create access key)"
    exit 1
fi

if [[ -n "$dry_run" ]]
then
    log "🧪 --dry-run: nothing changed. setup would validate the keys, then store AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION=$aws_region"
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

# 2. the IAM role of the assume-role variants
role_arn=""
second_key_id=""
second_secret=""
if [[ -n "$assume_role" ]]
then
    if [[ -n "$assume_role_profile" ]]
    then
        second_key_id=$(aws_setup_profile_value aws_access_key_id "$assume_role_profile")
        second_secret=$(aws_setup_profile_value aws_secret_access_key "$assume_role_profile")
    else
        profile="$(get_active_secret_profile)"
        second_key_id="$(secret_get AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID "$profile" 2> /dev/null || true)"
        second_secret="$(secret_get AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY "$profile" 2> /dev/null || true)"
    fi
    if [ -z "$second_key_id" ] || [ -z "$second_secret" ]
    then
        logerror "❌ --assume-role needs the keys of the second account (the principal that assumes the role): --assume-role-profile <profile>"
        exit 1
    fi
    if ! second_identity=$(aws_key_id="$second_key_id" aws_secret="$second_secret" aws_token="" aws_account_cli sts get-caller-identity 2>&1)
    then
        logerror "❌ AWS rejected the keys of the second account: $(aws_account_error_code "$second_identity")"
        exit 1
    fi
    second_arn=$(echo "$second_identity" | jq -r '.Arn')
    role_name="pg-assume-role-$(echo "${USER}" | tr -cd 'a-zA-Z0-9_+=,.@-')"
    role_arn="arn:aws:iam::$account_id:role/$role_name"
    trust=$(aws_assume_role_trust_policy "$second_arn")
    permissions=$(aws_assume_role_permission_policy)
    log "🎭 role $role_name, assumed by $second_arn with the external id 123"
    if [[ -n "$dry_run" ]]
    then
        log "🧪 --dry-run: trust policy of $role_name:"
        echo "$trust" | jq .
        log "🧪 --dry-run: permission policy pg-examples of $role_name:"
        echo "$permissions" | jq .
        exit 0
    fi
    if aws_account_cli iam get-role --role-name "$role_name" > /dev/null 2>&1
    then
        aws_account_cli iam update-assume-role-policy --role-name "$role_name" --policy-document "$trust" > /dev/null \
            || { logerror "❌ failed to update the trust policy of $role_name"; exit 1; }
        log "🎭 role $role_name already exists: trust policy updated"
    else
        if ! out=$(aws_account_cli iam create-role --role-name "$role_name" --assume-role-policy-document "$trust" \
            --description "assume-role variants of kafka-docker-playground" \
            --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER" 2>&1)
        then
            logerror "❌ failed to create the role $role_name: $(aws_account_error_code "$out") (the keys need iam:CreateRole and iam:PutRolePolicy)"
            exit 1
        fi
        log "🎭 created role $role_name"
    fi
    aws_account_cli iam put-role-policy --role-name "$role_name" --policy-name pg-examples --policy-document "$permissions" > /dev/null \
        || { logerror "❌ failed to attach the permission policy to $role_name"; exit 1; }
    # a cross-account principal also needs sts:AssumeRole on the role in its own account: say so, its keys may not allow iam changes
    second_account=$(echo "$second_identity" | jq -r '.Account')
    if [ "$second_account" != "$account_id" ]
    then
        logwarn "⚠️ the second account ($second_account) is another AWS account: its user also needs a policy allowing sts:AssumeRole on $role_arn"
    fi
    # IAM takes a few seconds to accept the new trust policy
    deadline=$((SECONDS + 90))
    until aws_key_id="$second_key_id" aws_secret="$second_secret" aws_token="" aws_account_cli sts assume-role --role-arn "$role_arn" \
        --role-session-name pg-setup --external-id 123 --duration-seconds 900 > /dev/null 2>&1
    do
        if [ $SECONDS -ge $deadline ]
        then
            logwarn "⚠️ the second account still can't assume $role_arn after 90 seconds: playground account aws check tells why"
            break
        fi
        sleep 10
    done
elif [[ -n "$dry_run" ]]
then
    exit 0
fi

# 3. store
if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export AWS_ACCESS_KEY_ID=\"$aws_key_id\""
    echo "export AWS_SECRET_ACCESS_KEY=\"$aws_secret\""
    echo "export AWS_REGION=\"$aws_region\""
    if [ -n "$role_arn" ]
    then
        echo "export AWS_STS_ROLE_ARN=\"$role_arn\""
        echo "export AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID=\"$second_key_id\""
        echo "export AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY=\"$second_secret\""
    fi
else
    playground secrets set AWS_ACCESS_KEY_ID --value "$aws_key_id" --secret
    playground secrets set AWS_SECRET_ACCESS_KEY --value "$aws_secret" --secret
    playground secrets set AWS_REGION --value "$aws_region" --plain
    stored="AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_REGION"
    if [ -n "$role_arn" ]
    then
        playground secrets set AWS_STS_ROLE_ARN --value "$role_arn" --plain
        playground secrets set AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID --value "$second_key_id" --secret
        playground secrets set AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY --value "$second_secret" --secret
        stored="$stored, AWS_STS_ROLE_ARN and AWS_ACCOUNT_WITH_ASSUME_ROLE_*"
    fi
    log "💾 stored $stored"
fi

log "🩺 what these credentials can do:"
check_env=(AWS_ACCESS_KEY_ID="$aws_key_id" AWS_SECRET_ACCESS_KEY="$aws_secret" AWS_REGION="$aws_region")
if [ -n "$role_arn" ]
then
    check_env+=(AWS_STS_ROLE_ARN="$role_arn" AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID="$second_key_id" AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY="$second_secret")
fi
env "${check_env[@]}" playground account aws check || true
log "🩺 check it any time with: playground account aws check"
