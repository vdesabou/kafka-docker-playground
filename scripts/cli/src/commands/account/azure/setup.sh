subscription="${args[--subscription]}"
current_login="${args[--current-login]}"
tenant_arg="${args[--tenant]}"
sp_name="${args[--service-principal]}"
new_secret="${args[--new-secret]}"
dry_run="${args[--dry-run]}"
no_store="${args[--no-store]}"

user_compact="$(echo "${USER}" | tr -d '._-' | tr '[:upper:]' '[:lower:]')"
if [[ ! -n "$sp_name" ]]
then
    sp_name="kdp-playground-$user_compact"
fi
if [ "$(echo "$sp_name" | tr '[:upper:]' '[:lower:]')" == "pg$user_compact" ]
then
    logerror "❌ --service-principal pg$user_compact is the app the data lake example resets the secrets of: pick another name"
    exit 1
fi
profile="$(get_active_secret_profile)"
if [[ ! -n "$subscription" ]]
then
    subscription="$(secret_get AZURE_SUBSCRIPTION_NAME "$profile" 2> /dev/null || true)"
fi

if [[ -n "$dry_run" ]]
then
    log "🧪 --dry-run: nothing changed. On subscription ${subscription:-<subscription>}, setup would:"
    log "🔌 register the resource providers (if not registered yet):"
    azure_setup_providers | while IFS='|' read -r provider examples
    do
        printf '   %-32s %s\n' "$provider" "$examples"
    done
    log "🤖 create the service principal $sp_name (or reuse it) and give it, on the subscription:"
    azure_setup_roles | while IFS='|' read -r role role_id why
    do
        printf '   %-40s %s\n' "$role" "$why"
    done
    log "🔑 add a client secret valid 1 year (or reuse the stored one while it works)"
    log "💾 store AZ_CLIENT_ID, AZ_CLIENT_SECRET, AZ_TENANT_ID, AZURE_SUBSCRIPTION_NAME and AZ_USER with playground secrets set"
    exit 0
fi

for tool in jq openssl curl
do
    if ! command -v $tool > /dev/null 2>&1
    then
        logerror "❌ $tool is not installed"
        exit 1
    fi
done
if ! command -v az > /dev/null 2>&1
then
    logerror "❌ the Azure CLI (az) is not installed"
    logerror "   install it: https://learn.microsoft.com/cli/azure/install-azure-cli (brew install azure-cli on macOS)"
    exit 1
fi
azure_tmp_dir=$(mktemp -d -t playground-azure-setup.XXXXXX)
chmod 700 "$azure_tmp_dir"
trap 'rm -rf "$azure_tmp_dir"' EXIT

# 1. the account
if [[ -n "$current_login" ]]
then
    azure_az_config=""
    if ! azure_az account show -o none > /dev/null 2>&1
    then
        logerror "❌ your az is not logged in (az account show): run az login, or run without --current-login"
        exit 1
    fi
else
    azure_az_config="${PLAYGROUND_SECRETS_DIR:-$HOME/.config/kafka-docker-playground}/azure"
    mkdir -p "$azure_az_config"
    if ! azure_az account show -o none > /dev/null 2>&1
    then
        log "🌐 log into Azure in the browser, with an account allowed to create service principals and assign roles"
        # no interactive subscription picker: the subscription is chosen below
        azure_az config set core.login_experience_v2=off --only-show-errors > /dev/null 2>&1 || true
        if ! azure_az login ${tenant_arg:+--tenant "$tenant_arg"} --only-show-errors -o none
        then
            logerror "❌ az login failed"
            exit 1
        fi
    fi
fi
az_user=$(azure_az account show --query user.name -o tsv 2> /dev/null) || true
log "👤 account $az_user"

# 2. the subscription
subscriptions=$(azure_az account list --query "[?state=='Enabled'].[name,id,tenantId]" -o tsv 2> /dev/null) || true
if [[ ! -n "$subscription" ]]
then
    if [ "$(echo "$subscriptions" | awk 'NF' | wc -l | tr -d ' ')" == "1" ]
    then
        subscription=$(echo "$subscriptions" | cut -f1)
    else
        logerror "❌ pass the subscription with --subscription, $az_user can see:"
        echo "$subscriptions" | cut -f1 | awk 'NF { print "   " $0 }' >&2
        exit 1
    fi
fi
subscription_id=$(echo "$subscriptions" | awk -F'\t' -v n="$subscription" '$1 == n { print $2; exit }')
tenant=$(echo "$subscriptions" | awk -F'\t' -v n="$subscription" '$1 == n { print $3; exit }')
if [ -z "$subscription_id" ]
then
    logerror "❌ subscription $subscription not found (or not enabled) for $az_user"
    exit 1
fi
scope="/subscriptions/$subscription_id"
log "🗂️ subscription $subscription ($subscription_id), tenant $tenant"

# 3. resource providers (registration is asynchronous: a few minutes)
registered=$(azure_az provider list --subscription "$subscription_id" --query "[?registrationState=='Registered'].namespace" -o tsv 2> /dev/null) || true
to_register=""
while IFS='|' read -r provider examples
do
    if ! echo "$registered" | grep -qix "$provider"
    then
        to_register="$to_register $provider"
    fi
done < <(azure_setup_providers)
if [[ -n "$to_register" ]]
then
    log "🔌 registering the resource providers:$to_register (asynchronous, a few minutes)"
    for provider in $to_register
    do
        azure_az provider register --namespace "$provider" --subscription "$subscription_id" --only-show-errors -o none < /dev/null \
            || logwarn "   ⚠️ could not register $provider (needs Contributor on the subscription)"
    done
else
    log "🔌 the $(azure_setup_providers | wc -l | tr -d ' ') resource providers of the examples are registered"
fi

# 4. the service principal
app_id=$(azure_az ad app list --display-name "$sp_name" --query "[0].appId" -o tsv 2> /dev/null) || true
client_secret=""
if [ -n "$app_id" ]
then
    log "🤖 service principal $sp_name already exists (app id $app_id)"
    stored_id="$(secret_get AZ_CLIENT_ID "$profile" 2> /dev/null || true)"
    stored_secret="$(secret_get AZ_CLIENT_SECRET "$profile" 2> /dev/null || true)"
    if [[ ! -n "$new_secret" ]] && [ "$stored_id" == "$app_id" ] && [ -n "$stored_secret" ] && azure_sp_token "$tenant" "$app_id" "$stored_secret" > /dev/null
    then
        client_secret="$stored_secret"
        log "🔑 reusing the stored client secret (it still logs in)"
    fi
    if ! azure_az ad sp show --id "$app_id" -o none > /dev/null 2>&1
    then
        azure_az ad sp create --id "$app_id" -o none --only-show-errors < /dev/null || { logerror "❌ failed to create the service principal of app $app_id"; exit 1; }
    fi
else
    log "🤖 creating service principal $sp_name"
    if ! azure_az ad app create --display-name "$sp_name" --sign-in-audience AzureADMyOrg --query appId -o tsv > "$azure_tmp_dir/app.out" 2> "$azure_tmp_dir/app.err" < /dev/null
    then
        logerror "❌ failed to create the app registration $sp_name: $(head -3 "$azure_tmp_dir/app.err")"
        logerror "   your account must be allowed to register applications in tenant $tenant (Entra ID > User settings), or ask an admin"
        exit 1
    fi
    app_id=$(tail -1 "$azure_tmp_dir/app.out")
    # a new app takes a few seconds to be visible
    attempt=1
    until azure_az ad sp create --id "$app_id" -o none --only-show-errors > /dev/null 2> "$azure_tmp_dir/sp.err" < /dev/null
    do
        if [ $attempt -ge 6 ]
        then
            logerror "❌ failed to create the service principal of app $app_id: $(head -3 "$azure_tmp_dir/sp.err")"
            exit 1
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
fi
if [ -z "$client_secret" ]
then
    # --append: the other secrets of the app (another machine, CI) keep working
    if ! client_secret=$(azure_az ad app credential reset --id "$app_id" --append --years 1 --display-name kdp-playground --query password -o tsv 2> "$azure_tmp_dir/secret.err" < /dev/null) || [ -z "$client_secret" ]
    then
        logerror "❌ failed to add a client secret to app $app_id: $(head -3 "$azure_tmp_dir/secret.err")"
        exit 1
    fi
    log "🔑 added a client secret to $sp_name, valid 1 year"
fi
sp_oid=$(azure_az ad sp show --id "$app_id" --query id -o tsv 2> /dev/null) || true

# 5. roles on the subscription
nb_granted=0
nb_role_failed=0
while IFS='|' read -r role role_id why
do
    # < /dev/null: az reads stdin, and would swallow the next roles of the loop
    # --subscription: without a current subscription in az (MissingSubscription), even with --scope
    count=$(azure_az role assignment list --subscription "$subscription_id" --assignee "$app_id" --scope "$scope" --role "$role" --include-inherited --query "length(@)" -o tsv 2> /dev/null < /dev/null) || count=""
    if [ "${count:-0}" != "0" ]
    then
        continue
    fi
    # a new service principal takes a few seconds to be visible to role assignments
    granted=""
    for attempt in 1 2 3 4
    do
        if azure_az role assignment create --subscription "$subscription_id" --assignee-object-id "$sp_oid" --assignee-principal-type ServicePrincipal \
            --role "$role" --scope "$scope" -o none --only-show-errors > /dev/null 2> "$azure_tmp_dir/role.err" < /dev/null
        then
            granted=1
            break
        fi
        sleep 10
    done
    if [[ -n "$granted" ]]
    then
        nb_granted=$((nb_granted + 1))
    else
        nb_role_failed=$((nb_role_failed + 1))
        logwarn "⚠️ could not give $role to $sp_name: $(grep -m1 -i 'error\|authoriz' "$azure_tmp_dir/role.err" | cut -c1-200)"
        logwarn "   your account needs Owner or User Access Administrator on the subscription; needed for: $why"
    fi
done < <(azure_setup_roles)
log "🎭 roles of $sp_name on the subscription checked ($nb_granted given now)"

# 6. wait until the service principal can log in (a new secret takes up to a minute)
deadline=$((SECONDS + 180))
until azure_sp_token "$tenant" "$app_id" "$client_secret" > "$azure_tmp_dir/token.out"
do
    if [ $SECONDS -ge $deadline ]
    then
        logerror "❌ the service principal still can't log in after 180 seconds: $(cat "$azure_tmp_dir/token.out")"
        exit 1
    fi
    sleep 10
done
log "✅ service principal $sp_name can log in"
end_date=$(azure_az ad app credential list --id "$app_id" --query "[?displayName=='kdp-playground'].endDateTime | sort(@) | [-1]" -o tsv 2> /dev/null) || true
if [ -n "$end_date" ]
then
    log "📅 its client secret expires on ${end_date%%T*}: run setup again before (with --new-secret)"
fi

# 7. store
if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export AZ_CLIENT_ID=\"$app_id\""
    echo "export AZ_CLIENT_SECRET=\"$client_secret\""
    echo "export AZ_TENANT_ID=\"$tenant\""
    echo "export AZURE_SUBSCRIPTION_NAME=\"$subscription\""
    echo "export AZ_USER=\"$az_user\""
else
    playground secrets set AZ_CLIENT_ID --value "$app_id" --plain
    playground secrets set AZ_CLIENT_SECRET --value "$client_secret" --secret
    playground secrets set AZ_TENANT_ID --value "$tenant" --plain
    playground secrets set AZURE_SUBSCRIPTION_NAME --value "$subscription" --plain
    if [ -n "$az_user" ]
    then
        # the owner_email tag of the resource groups: with a service principal login, az would give its app id
        playground secrets set AZ_USER --value "$az_user" --plain
    fi
    log "💾 stored AZ_CLIENT_ID, AZ_CLIENT_SECRET, AZ_TENANT_ID, AZURE_SUBSCRIPTION_NAME and AZ_USER"
fi

# 8. check, waiting for the roles given now to apply
check_out="$azure_tmp_dir/check.out"
if [ $nb_granted -gt 0 ]
then
    log "⏳ waiting for the $nb_granted new roles to apply (max 180 seconds)"
    deadline=$((SECONDS + 180))
    until AZ_CLIENT_ID="$app_id" AZ_CLIENT_SECRET="$client_secret" AZ_TENANT_ID="$tenant" \
        playground account azure check --subscription "$subscription" > "$check_out" 2>&1 && grep -q "is ready for the Azure examples" "$check_out"
    do
        if [ $SECONDS -ge $deadline ]
        then
            break
        fi
        sleep 20
    done
else
    AZ_CLIENT_ID="$app_id" AZ_CLIENT_SECRET="$client_secret" AZ_TENANT_ID="$tenant" \
        playground account azure check --subscription "$subscription" > "$check_out" 2>&1 || true
fi
log "🩺 what the service principal can do on $subscription:"
cat "$check_out"
log "🩺 check it any time with: playground account azure check"
