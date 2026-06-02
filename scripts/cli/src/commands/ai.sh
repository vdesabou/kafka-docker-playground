arguments="${args[arguments]}"

cd $root_folder

get_environment_used

set +e
docker pull vdesabou/mcp-playground-server:latest > /dev/null 2>&1
set -e

if [[ "$environment" == "ccloud" ]]
then
    if [ -f .ccloud/.env ]
    then
        log "🌩️ ccloud environment is used, using mcp-confluent server (https://github.com/confluentinc/mcp-confluent) to interact with confluent cloud"
        claude mcp remove mcp-kafka > /dev/null 2>&1 || true
        claude mcp remove mcp-ccloud > /dev/null 2>&1 || true
        cd $root_folder > /dev/null
        source .ccloud/.env
        # generate data file for externalizing secrets
        sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
            -e "s|:KAFKA_API_KEY:|$KAFKA_API_KEY|g" \
            -e "s|:KAFKA_API_SECRET:|$KAFKA_API_SECRET|g" \
            -e "s|:KAFKA_REST_ENDPOINT:|$KAFKA_REST_ENDPOINT|g" \
            -e "s|:KAFKA_CLUSTER_ID:|$KAFKA_CLUSTER_ID|g" \
            -e "s|:KAFKA_ENV_ID:|$KAFKA_ENV_ID|g" \
            -e "s|:SCHEMA_REGISTRY_ENDPOINT:|$SCHEMA_REGISTRY_ENDPOINT|g" \
            -e "s|:SCHEMA_REGISTRY_API_KEY:|$SCHEMA_REGISTRY_API_KEY|g" \
            -e "s|:SCHEMA_REGISTRY_API_SECRET:|$SCHEMA_REGISTRY_API_SECRET|g" \
            -e "s|:CONFLUENT_CLOUD_REST_ENDPOINT:|$CONFLUENT_CLOUD_REST_ENDPOINT|g" \
            -e "s|:CONFLUENT_CLOUD_API_KEY:|$CONFLUENT_CLOUD_API_KEY|g" \
            -e "s|:CONFLUENT_CLOUD_API_SECRET:|$CONFLUENT_CLOUD_API_SECRET|g" \
            $root_folder/scripts/cli/src/mcp-confluent-config-ccloud-template.yaml > $root_folder/config.yaml

        claude mcp add mcp-ccloud -- npx -y @confluentinc/mcp-confluent --config ./config.yaml
        cd - > /dev/null
    else
        logerror "❌ .ccloud/.env file is not present!"
        exit 1
    fi
else
    claude mcp remove mcp-ccloud > /dev/null 2>&1 || true

    if [[ "$environment" == "plaintext" ]]
    then
        log "📭 plaintext environment is used, using mcp-confluent server (https://github.com/confluentinc/mcp-confluent) to interact with the cluster"
        claude mcp remove mcp-kafka > /dev/null 2>&1 || true
        cd $root_folder > /dev/null
        cp $root_folder/scripts/cli/src/mcp-confluent-config-local.yaml config.yaml
        claude mcp add mcp-kafka -- npx -y @confluentinc/mcp-confluent --config ./config.yaml 
        cd - > /dev/null
    else
        logwarn "🔐 $environment environment is used, using mcp-confluent server (https://github.com/confluentinc/mcp-confluent) to interact with the cluster will not be used, only works with plaintext for now"
    fi
fi

log "🧞‍♂️ calling claude cli: claude ${other_args[*]}"
claude "${other_args[*]}"