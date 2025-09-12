containers="${args[--container]}"
# Convert the space delimited string to an array
eval "operations=(${args[--operation]})"
class="${args[--class]}"
method="${args[--method]}"
action="${args[--action]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	if [[ "$action" == "enable" ]]
	then
		operation_string=$(printf "+%s" "${operations[@]}")
		# remove + at beginning and end of operation_string
		operation_string=${operation_string%+}
		operation_string=${operation_string#+}

		log "🔧 enabling jscissors for container ${container} with operation(s) ${operation_string}, class ${class} and method ${method}"
		echo "${class}{${method}}=$operation_string" > /tmp/scissors.props

		playground container set-environment-variables --container "${container}" --env "_JAVA_OPTIONS: -javaagent:/tmp/jscissors-1.0-SNAPSHOT.jar=configFile=/tmp/scissors.props" --mount-jscissors-files

		playground container logs --container "${container}" --wait-for-log "Core Logger" --max-wait 30

		scissors_file=$(playground --output-level WARN container logs --container "${container}" --wait-for-log "Core Logger" | tail -1 | cut -d " " -f 4)

		log "✂️ jscissors file is available ${scissors_file}"
		playground open --file "${scissors_file}"
	else
		playground container set-environment-variables --container "${container}" --restore-original-values
	fi
done