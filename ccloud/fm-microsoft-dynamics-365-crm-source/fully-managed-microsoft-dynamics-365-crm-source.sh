#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# if DYNAMICS365_URL, DYNAMICS365_TENANT_ID, DYNAMICS365_CLIENT_ID and DYNAMICS365_CLIENT_SECRET are all set, the existing
# environment is used. Otherwise a Power Platform environment, an Entra app and a Dataverse application user are created
# and deleted at the end of the run
# set DYNAMICS365_KEEP_RESOURCES=1 to keep the created environment and Entra app, for example to use them in CI
DYNAMICS365_ENVIRONMENT_SKU=${DYNAMICS365_ENVIRONMENT_SKU:-Developer}
# depending on the tenant provisioning mode, environments are placed by location or by macro region
DYNAMICS365_ENVIRONMENT_LOCATION=${DYNAMICS365_ENVIRONMENT_LOCATION:-europe}
DYNAMICS365_ENVIRONMENT_MACRO_REGION=${DYNAMICS365_ENVIRONMENT_MACRO_REGION:-eu-efta}

BAP_API="https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform"
BAP_API_VERSION="api-version=2023-06-01"

function bap_api {
    method="$1"
    path="$2"
    shift 2
    curl -s --fail-with-body -X "$method" "$BAP_API/$path" \
        -H "Authorization: Bearer $(az account get-access-token --resource https://service.powerapps.com/ --query accessToken -o tsv)" \
        -H "Content-Type: application/json" \
        "$@"
}

# call the Dataverse Web API, with $DYNAMICS365_TOKEN
function dataverse_api {
    method="$1"
    path="$2"
    shift 2
    curl -s --fail-with-body -X "$method" "$DYNAMICS365_URL/api/data/v9.2/$path" \
        -H "Authorization: Bearer $DYNAMICS365_TOKEN" \
        -H "OData-MaxVersion: 4.0" \
        -H "OData-Version: 4.0" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json; charset=utf-8" \
        "$@"
}

# environments being deleted (deletion is asynchronous) are ignored
function get_environment_name_by_display_name {
    bap_api GET "environments?$BAP_API_VERSION" | jq -r --arg d "$1" '.value[] | select(.properties.displayName == $d and .properties.provisioningState != "Deleting") | .name'
}

function delete_environment {
    env_name="$1"
    log "Deleting Power Platform environment $env_name"
    delete_body='{"Code": "7", "Message": "Deleted by kafka-docker-playground"}'
    if ! response=$(bap_api DELETE "scopes/admin/environments/$env_name?$BAP_API_VERSION" -d "$delete_body")
    then
        if ! response=$(bap_api DELETE "environments/$env_name?$BAP_API_VERSION" -d "$delete_body")
        then
            logwarn "Failed to delete environment $env_name (it might be already being deleted): $response"
        fi
    fi
}

ENVIRONMENT_NAME=""
CREATED_APP_ID=""
ACCOUNT_IDS=""

function cleanup_cloud_resources {
    set +e
    if [ -n "$CREATED_APP_ID" ] && [ -n "$DYNAMICS365_KEEP_RESOURCES" ]
    then
        log "DYNAMICS365_KEEP_RESOURCES is set, keeping Power Platform environment $ENVIRONMENT_DISPLAY_NAME and Entra app $CREATED_APP_ID. To re-use them, set:"
        echo "DYNAMICS365_URL=$DYNAMICS365_URL"
        echo "DYNAMICS365_TENANT_ID=$DYNAMICS365_TENANT_ID"
        echo "DYNAMICS365_CLIENT_ID=$DYNAMICS365_CLIENT_ID"
        echo "DYNAMICS365_CLIENT_SECRET=$DYNAMICS365_CLIENT_SECRET"
        for id in $ACCOUNT_IDS
        do
            log "Deleting account $id"
            dataverse_api DELETE "accounts($id)"
        done
    elif [ -n "$CREATED_APP_ID" ]
    then
        log "Deleting Power Platform environment $ENVIRONMENT_DISPLAY_NAME and Entra app $CREATED_APP_ID"
        check_if_continue
        if [ -n "$ENVIRONMENT_NAME" ]
        then
            delete_environment "$ENVIRONMENT_NAME"
        fi
        az ad app delete --id "$CREATED_APP_ID"
    else
        for id in $ACCOUNT_IDS
        do
            log "Deleting account $id"
            dataverse_api DELETE "accounts($id)"
        done
    fi
}
trap cleanup_cloud_resources EXIT

if [ -n "$DYNAMICS365_URL" ] && [ -n "$DYNAMICS365_TENANT_ID" ] && [ -n "$DYNAMICS365_CLIENT_ID" ] && [ -n "$DYNAMICS365_CLIENT_SECRET" ]
then
    log "💡 DYNAMICS365_URL, DYNAMICS365_TENANT_ID, DYNAMICS365_CLIENT_ID and DYNAMICS365_CLIENT_SECRET are set, using existing environment $DYNAMICS365_URL"
else
    if [ -n "$GITHUB_RUN_NUMBER" ]
    then
        logerror "❌ automatic provisioning of a Power Platform environment requires a user login, set DYNAMICS365_URL, DYNAMICS365_TENANT_ID, DYNAMICS365_CLIENT_ID and DYNAMICS365_CLIENT_SECRET"
        exit 1
    fi
    login_and_maybe_set_azure_subscription

    DYNAMICS365_TENANT_ID=$(az account show --query tenantId -o tsv)
    ENVIRONMENT_DISPLAY_NAME=pg${USER}fmd365${TAG_BASE}
    if [ -n "$DYNAMICS365_KEEP_RESOURCES" ]
    then
        ENVIRONMENT_DISPLAY_NAME=pg${USER}fmd365keep
    fi
    ENVIRONMENT_DISPLAY_NAME=${ENVIRONMENT_DISPLAY_NAME//[-._]/}
    # domain name must be unique
    ENVIRONMENT_DOMAIN=${ENVIRONMENT_DISPLAY_NAME}$RANDOM

    for env_name in $(get_environment_name_by_display_name "$ENVIRONMENT_DISPLAY_NAME")
    do
        log "Power Platform environment $ENVIRONMENT_DISPLAY_NAME already exists"
        delete_environment "$env_name"
    done

    # created before the environment, as it takes some time for a new app to be visible from Dataverse
    AZURE_APP_NAME=${ENVIRONMENT_DISPLAY_NAME}-app
    log "Creating Entra app/service principal $AZURE_APP_NAME"
    DYNAMICS365_CLIENT_ID=$(az ad app create --display-name "$AZURE_APP_NAME" --query appId -o tsv)
    CREATED_APP_ID=$DYNAMICS365_CLIENT_ID
    az ad sp create --id "$DYNAMICS365_CLIENT_ID" > /dev/null
    DYNAMICS365_CLIENT_SECRET=$(az ad app credential reset --id "$DYNAMICS365_CLIENT_ID" --append --query password -o tsv)

    PROVISIONING_MODE=$(bap_api GET "locations?$BAP_API_VERSION" | jq -r '.tenantProvisioningMode // empty')
    if [ "$PROVISIONING_MODE" == "macroRegion" ]
    then
        PLACEMENT="\"macroRegion\": \"$DYNAMICS365_ENVIRONMENT_MACRO_REGION\""
        log "Tenant provisions environments by macro region, using macro region $DYNAMICS365_ENVIRONMENT_MACRO_REGION"
    else
        PLACEMENT="\"location\": \"$DYNAMICS365_ENVIRONMENT_LOCATION\""
        log "Tenant provisions environments by location, using location $DYNAMICS365_ENVIRONMENT_LOCATION"
    fi

    log "Creating Power Platform $DYNAMICS365_ENVIRONMENT_SKU environment $ENVIRONMENT_DISPLAY_NAME with Dataverse, this takes a few minutes"
    bap_api POST "environments?$BAP_API_VERSION" -D /tmp/d365-create-headers.txt -o /tmp/d365-create-body.json -d "{
        $PLACEMENT,
        \"properties\": {
            \"displayName\": \"$ENVIRONMENT_DISPLAY_NAME\",
            \"description\": \"used by kafka-docker-playground\",
            \"environmentSku\": \"$DYNAMICS365_ENVIRONMENT_SKU\",
            \"databaseType\": \"CommonDataService\",
            \"linkedEnvironmentMetadata\": {
                \"baseLanguage\": 1033,
                \"domainName\": \"$ENVIRONMENT_DOMAIN\",
                \"currency\": { \"code\": \"EUR\" }
            }
        }
    }" || { logerror "❌ failed to create environment"; cat /tmp/d365-create-body.json; exit 1; }

    MAX_WAIT=1200
    CUR_WAIT=0
    DYNAMICS365_URL=""
    while [ -z "$DYNAMICS365_URL" ]
    do
        sleep 30
        CUR_WAIT=$(( CUR_WAIT+30 ))
        ENVIRONMENT_NAME=$(get_environment_name_by_display_name "$ENVIRONMENT_DISPLAY_NAME" | head -1)
        if [ -n "$ENVIRONMENT_NAME" ]
        then
            environment=$(bap_api GET "environments/$ENVIRONMENT_NAME?$BAP_API_VERSION")
            state=$(echo "$environment" | jq -r '.properties.provisioningState')
            instance_state=$(echo "$environment" | jq -r '.properties.linkedEnvironmentMetadata.instanceState // empty')
            log "⏳ environment $ENVIRONMENT_NAME provisioning state: $state, Dataverse instance state: $instance_state"
            if [ "$state" == "Succeeded" ] && [ "$instance_state" == "Ready" ]
            then
                DYNAMICS365_URL=$(echo "$environment" | jq -r '.properties.linkedEnvironmentMetadata.instanceUrl')
            fi
        else
            log "⏳ environment $ENVIRONMENT_DISPLAY_NAME not yet listed"
        fi
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ environment $ENVIRONMENT_DISPLAY_NAME was not ready after $MAX_WAIT seconds"
            exit 1
        fi
    done
    DYNAMICS365_URL=${DYNAMICS365_URL%/}
    log "✅ Dataverse environment is ready: $DYNAMICS365_URL"

    # the current user is System Administrator of the environment it created, but the Web API can take a few minutes to
    # accept its requests after the environment is reported as ready
    log "Waiting for Dataverse Web API to accept requests from $(az account show --query user.name -o tsv)"
    BUSINESS_UNIT_ID=""
    for i in {1..20}
    do
        DYNAMICS365_TOKEN=$(az account get-access-token --resource "$DYNAMICS365_URL" --query accessToken -o tsv)
        if response=$(dataverse_api GET "WhoAmI")
        then
            BUSINESS_UNIT_ID=$(echo "$response" | jq -r '.BusinessUnitId // empty')
        fi
        if [ -n "$BUSINESS_UNIT_ID" ]
        then
            break
        fi
        if [ $i -eq 20 ]
        then
            logerror "❌ Dataverse Web API WhoAmI failed: $response"
            exit 1
        fi
        log "⏳ Dataverse Web API not ready yet, retrying in 15 seconds ($i/20): $response"
        sleep 15
    done

    log "Creating Dataverse application user for app $DYNAMICS365_CLIENT_ID in business unit $BUSINESS_UNIT_ID"
    APPLICATION_USER_ID=""
    for i in {1..20}
    do
        if response=$(dataverse_api POST "systemusers" -H "Prefer: return=representation" -d "{
            \"applicationid\": \"$DYNAMICS365_CLIENT_ID\",
            \"businessunitid@odata.bind\": \"/businessunits($BUSINESS_UNIT_ID)\"
        }")
        then
            APPLICATION_USER_ID=$(echo "$response" | jq -r '.systemuserid')
            break
        fi
        if [ $i -eq 20 ]
        then
            logerror "❌ failed to create application user: $response"
            exit 1
        fi
        # a newly created Entra app can take a few minutes to be found by Dataverse
        log "⏳ application user could not be created yet, retrying in 15 seconds ($i/20): $response"
        sleep 15
    done

    log "Assigning System Administrator security role to application user $APPLICATION_USER_ID"
    response=$(dataverse_api GET "roles?\$select=roleid&\$filter=name%20eq%20'System%20Administrator'%20and%20_businessunitid_value%20eq%20$BUSINESS_UNIT_ID") || { logerror "❌ failed to get System Administrator role: $response"; exit 1; }
    ROLE_ID=$(echo "$response" | jq -r '.value[0].roleid')
    response=$(dataverse_api POST "systemusers($APPLICATION_USER_ID)/systemuserroles_association/\$ref" -d "{\"@odata.id\": \"$DYNAMICS365_URL/api/data/v9.2/roles($ROLE_ID)\"}") || { logerror "❌ failed to assign role $ROLE_ID: $response"; exit 1; }
fi

DYNAMICS365_URL=${DYNAMICS365_URL%/}
DYNAMICS365_TOKEN_URL="https://login.microsoftonline.com/$DYNAMICS365_TENANT_ID/oauth2/v2.0/token"

log "Getting an access token for $DYNAMICS365_URL using client credentials"
# a newly created client secret can take some time to be usable
for i in {1..10}
do
    DYNAMICS365_TOKEN=$(curl -s -X POST "$DYNAMICS365_TOKEN_URL" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$DYNAMICS365_CLIENT_ID" \
        --data-urlencode "client_secret=$DYNAMICS365_CLIENT_SECRET" \
        --data-urlencode "scope=$DYNAMICS365_URL/.default" | jq -r '.access_token // empty')
    if [ -n "$DYNAMICS365_TOKEN" ] && dataverse_api GET "WhoAmI" > /dev/null
    then
        break
    fi
    if [ $i -eq 10 ]
    then
        logerror "❌ could not call Dataverse Web API with client id $DYNAMICS365_CLIENT_ID"
        exit 1
    fi
    log "⏳ client credentials not usable yet, retrying in 15 seconds ($i/10)"
    sleep 15
done

log "Checking if change tracking is enabled for table account"
CHANGE_TRACKING_ENABLED=$(dataverse_api GET "EntityDefinitions(LogicalName='account')?\$select=ChangeTrackingEnabled" | jq -r '.ChangeTrackingEnabled')
log "Change tracking enabled for table account: $CHANGE_TRACKING_ENABLED"
if [ "$CHANGE_TRACKING_ENABLED" != "true" ]
then
    logwarn "Change tracking is not enabled for table account, versionnumber column will be used as watermark (deletes are not captured)"
    CHANGE_TRACKING_ENABLED=false
fi

# retry until the account is found in topic crmaccounts
function wait_for_account_in_topic {
    name="$1"
    for i in {1..10}
    do
        if playground topic consume --topic crmaccounts --min-expected-messages 1 --max-messages -1 --timeout 60 --grep "$name"
        then
            return 0
        fi
        log "⏳ account $name not yet in topic crmaccounts, retrying in 20 seconds ($i/10)"
        sleep 20
    done
    logerror "❌ account $name was not found in topic crmaccounts"
    exit 1
}

ACCOUNT_NAME="playground-account-${USER}-${GITHUB_RUN_NUMBER}${TAG_BASE}-$RANDOM"

function create_account {
    name="$1"
    id=$(dataverse_api POST "accounts" -H "Prefer: return=representation" -d "{\"name\": \"$name\", \"description\": \"created by kafka-docker-playground\"}" | jq -r '.accountid')
    log "Created account $name with id $id"
    ACCOUNT_IDS="$ACCOUNT_IDS $id"
}

create_account "$ACCOUNT_NAME-1"

bootstrap_ccloud_environment

set +e
playground topic delete --topic crmaccounts
set -e

connector_name="MicrosoftDynamics365CRMSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MicrosoftDynamics365CRMSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "dynamics365.url": "$DYNAMICS365_URL",
  "oauth2.token.url": "$DYNAMICS365_TOKEN_URL",
  "oauth2.client.id": "$DYNAMICS365_CLIENT_ID",
  "oauth2.client.secret": "$DYNAMICS365_CLIENT_SECRET",
  "output.data.format": "JSON",
  "dynamics365.topic.prefix": "crm",
  "entities.num": "1",
  "entity1.name": "accounts",
  "entity1.change.tracking.enabled": "$CHANGE_TRACKING_ENABLED",
  "poll.interval.ms": "5000",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verifying initial load: account $ACCOUNT_NAME-1 is in topic crmaccounts"
wait_for_account_in_topic "$ACCOUNT_NAME-1"

create_account "$ACCOUNT_NAME-2"

log "Verifying incremental load: account $ACCOUNT_NAME-2 is in topic crmaccounts"
wait_for_account_in_topic "$ACCOUNT_NAME-2"

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
