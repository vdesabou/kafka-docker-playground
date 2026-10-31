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
		
		# append to the KAFKA_OPTS the container already has: the brokers of the SASL / Kerberos environments need their
		# -Djava.security.auth.login.config, connect its -Ddynamic.worker.config.file=/dev/null
		current_opts=$(get_container_env_value "${container}" KAFKA_OPTS)
		if [[ " ${current_opts} " == *" ${OPTS} "* ]]
		then
			log "💫 ${OPTS} is already in KAFKA_OPTS of ${container}"
			continue
		fi
		new_opts=$(echo "${current_opts} ${OPTS}" | sed -e 's/^ *//')
		log "☕ KAFKA_OPTS of ${container}: ${new_opts}"
		playground container set-environment-variables --container "${container}" --env "KAFKA_OPTS: ${new_opts}"
	else
		playground container set-environment-variables --container "${container}" --restore-original-values
	fi
done