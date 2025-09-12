containers="${args[--container]}"
type="${args[--type]}"
action="${args[--action]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	if [[ "$action" == "enable" ]]
	then
		case "${type}" in
			"ssl_all")
				OPTS="-Djavax.net.debug=all"
			;;
			"ssl_handshake")
				OPTS="-Djavax.net.debug=ssl:handshake"
			;;
			"class_loading")
				OPTS="-verbose:class"
			;;
			"kerberos")
				OPTS="-Dsun.security.krb5.debug=true"
			;;
		esac
		
		playground container set-environment-variables --container "${container}" --env "KAFKA_OPTS: ${OPTS}"
	else
		playground container set-environment-variables --container "${container}" --restore-original-values
	fi
done