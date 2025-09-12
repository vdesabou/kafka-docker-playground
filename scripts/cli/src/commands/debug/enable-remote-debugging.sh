containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "✨ enable remote debugging for $container"
	playground container set-environment-variables --container "${container}" --env "KAFKA_DEBUG: 'true'" --env "JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'"

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

	log "See https://kafka-docker-playground.io/#/reusables?id=✨-remote-debugging"
done