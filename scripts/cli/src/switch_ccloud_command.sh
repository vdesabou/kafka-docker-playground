log "🌩️ switch to ccloud environment"

ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)
CLUSTER_NAME=$(playground state get ccloud.CLUSTER_NAME)
CLUSTER_CLOUD=$(playground state get ccloud.CLUSTER_CLOUD)
CLUSTER_REGION=$(playground state get ccloud.CLUSTER_REGION)
CLUSTER_CREDS=$(playground state get ccloud.CLUSTER_CREDS)
SCHEMA_REGISTRY_CREDS=$(playground state get ccloud.SCHEMA_REGISTRY_CREDS)

if [ -z $ENVIRONMENT ] || [ -z $CLUSTER_CLOUD ] || [ -z $CLUSTER_CLOUD ] || [ -z $CLUSTER_REGION ] || [ -z $CLUSTER_CREDS ]
then
    logerror "One mandatory environment variable to use your cluster is missing:"
    logerror "ENVIRONMENT=$ENVIRONMENT"
    logerror "CLUSTER_NAME=$CLUSTER_NAME"
    logerror "CLUSTER_CLOUD=$CLUSTER_CLOUD"
    logerror "CLUSTER_REGION=$CLUSTER_REGION"
    logerror "CLUSTER_CREDS=$CLUSTER_CREDS"
    exit 1
fi

playground state set run.environment_before_switch "$(playground state get run.environment)"

log "🔌 boostrapping ccloud environment"
bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
    source /tmp/delta_configs/env.delta
else
    logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
    exit 1
fi