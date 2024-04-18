IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

container="${args[--container]}"
domain="${args[--domain]}"
open="${args[--open]}"

case "${container}" in
  zookeeper|broker|schema-registry|connect|connect2|connect3)
  ;;
  *)
    logerror "ERROR: container name not valid ! Should be one of zookeeper, broker, schema-registry, connect, connect2 or connect3"
    exit 1
  ;;
esac

get_jmx_metrics "$container" "$domain" "$open"