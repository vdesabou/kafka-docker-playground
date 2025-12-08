containers="${args[--container]}"
skip_vs_code_config_display="${args[--skip-vs-code-config-display]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    if [[ "$container" == connect* ]]
    then
        log "💫 enable-remote-debugging is already enabled for connect container $container"
        continue
    fi
    log "✨ enable remote debugging for $container"
    playground container set-environment-variables --container "${container}" --env "KAFKA_DEBUG: 'true'" --env "JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'"

    if [[ ! -n "$skip_vs_code_config_display" ]]
    then
        log "If you use Visual Studio Code:"
        log "Edit .vscode/launch.json with"

        log "
        {
            \"version\": \"0.2.0\",
            \"configurations\": [
            
                {
                    \"type\": \"java\",
                    \"name\": \"Debug $component container\",
                    \"request\": \"attach\",
                    \"hostName\": \"127.0.0.1\",
                    \"port\": 5005,
                    \"timeout\": 30000
                }
            ]
        }
        "
    fi

    log "see https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging"
done