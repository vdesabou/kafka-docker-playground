IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

containers="${args[--container]}"
domain="${args[--domain]}"
open="${args[--open]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	case "${container}" in
	zookeeper|zookeeper2|zookeeper3|broker|schema-registry|connect|connect2|connect3|controller|controller2|controller3|connect-[0-9]*)
	;;
	*)
		logerror "❌ container name not valid ! Should be one of zookeeper, zookeeper2, zookeeper3, controller, controller2, controller3, broker, schema-registry, connect, connect2, connect3 or connect-<n>"
		exit 1
	;;
	esac

	get_jmx_metrics "$container" "$domain" "$open"
done


