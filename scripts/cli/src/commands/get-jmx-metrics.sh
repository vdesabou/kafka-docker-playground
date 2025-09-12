IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

containers="${args[--container]}"
domain="${args[--domain]}"
open="${args[--open]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	case "${container}" in
	zookeeper|broker|schema-registry|connect|connect2|connect3|controller)
	;;
	*)
		logerror "❌ container name not valid ! Should be one of zookeeper, controller, broker, schema-registry, connect, connect2 or connect3"
		exit 1
	;;
	esac

	get_jmx_metrics "$container" "$domain" "$open"
done


