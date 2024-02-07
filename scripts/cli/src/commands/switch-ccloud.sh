log "🌩️ switch to ccloud environment"

for item in {ENVIRONMENT,CLUSTER_NAME,CLUSTER_CLOUD,CLUSTER_REGION,CLUSTER_CREDS,SCHEMA_REGISTRY_CREDS}
do
    i=$(playground state get "ccloud.${item}")
    if [ "$i" == "" ]
    then
        logerror "ccloud.${item} is missing"
        logerror "a ccloud example was probably not executed before"
        exit 1
    fi
done

ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)
CLUSTER_NAME=$(playground state get ccloud.CLUSTER_NAME)
CLUSTER_CLOUD=$(playground state get ccloud.CLUSTER_CLOUD)
CLUSTER_REGION=$(playground state get ccloud.CLUSTER_REGION)
CLUSTER_CREDS=$(playground state get ccloud.CLUSTER_CREDS)
SCHEMA_REGISTRY_CREDS=$(playground state get ccloud.SCHEMA_REGISTRY_CREDS)

playground state set run.environment_before_switch "$(playground state get run.environment)"
playground state set run.connector_type_before_switch "$(playground state get run.connector_type)"
playground state set run.connector_type "$CONNECTOR_TYPE_FULLY_MANAGED"

log "🔌 boostrapping ccloud environment"
bootstrap_ccloud_environment