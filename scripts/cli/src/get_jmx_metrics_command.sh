IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

component="${args[--component]}"
domain="${args[--domain]}"

case "${component}" in
  zookeeper|broker|schema-registry|connect)
  ;;
  *)
    logerror "ERROR: component name not valid ! Should be one of zookeeper, broker, schema-registry or connect"
    exit 1
  ;;
esac

get_jmx_metrics "$component" "$domain"