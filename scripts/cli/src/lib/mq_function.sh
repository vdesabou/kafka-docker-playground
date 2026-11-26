# helpers of 'playground mq put|get|wait': the message broker of a source (or sink) example, with the client that is
# already in its container (IBM MQ samples amqsput / amqsbcg / runmqsc, mosquitto_pub / mosquitto_sub, rabbitmqctl) or
# its HTTP API called from a curl container that joins its network namespace (RabbitMQ management, ActiveMQ REST and
# Jolokia, Solace REST messaging and SEMP), so no client is installed on the host

MQ_SUPPORTED_BROKERS="ibmmq, rabbitmq, mqtt (mosquitto), activemq (classic), solace"
MQ_CURL_IMAGE="curlimages/curl:latest"

# broker of an image or container name, empty when it is not one
function mq_broker_from_name () {
  local name="${1,,}"
  case "$name" in
    *producer*|*consumer*) return 1 ;;
    *ibm-messaging/mq*|*ibmcom/mq*|*ibmmq*|*ibm-mq*) echo "ibmmq" ;;
    *rabbitmq*) echo "rabbitmq" ;;
    *mosquitto*) echo "mqtt" ;;
    *artemis*) return 1 ;;
    *activemq*) echo "activemq" ;;
    *solace*) echo "solace" ;;
    *) return 1 ;;
  esac
}

function mq_list_running () {
  if [[ "$mq_transport" == "kubectl" ]]
  then
    kubectl -n confluent get pods --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null
  else
    docker ps --filter "status=running" --format '{{.Names}}{{"\t"}}{{.Image}}' 2>/dev/null
  fi
}

# runs a command in the broker container (docker exec, or kubectl exec in the pod on cfk), stdin passed through
function mq_exec () {
  if [[ "$mq_transport" == "kubectl" ]]
  then
    kubectl -n confluent exec -i "$mq_container" -- "$@"
  else
    docker exec -i "$mq_container" "$@"
  fi
}

# value of an environment variable of the container
function mq_container_env () {
  if [[ "$mq_transport" == "kubectl" ]]
  then
    kubectl -n confluent get pod "$mq_container" -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null | sed -n "s/^$1=//p" | head -1
  else
    docker inspect "$mq_container" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n "s/^$1=//p" | head -1
  fi
}

# sets mq_container and mq_broker: mq_resolve_container <container> <broker>
function mq_resolve_container () {
  local wanted_container="$1" wanted_broker="$2" name image broker
  mq_container=""
  mq_broker=""
  mq_transport="docker"
  mq_kind="container"
  get_environment_used
  if [[ "$environment" == cfk* ]]
  then
    mq_transport="kubectl"
    mq_kind="pod"
  fi
  if [[ -n "$wanted_container" ]]
  then
    if [[ "$mq_transport" == "kubectl" ]]
    then
      wanted_container=$(resolve_container_name_for_environment "$wanted_container")
    fi
    image=$(mq_list_running | awk -F'\t' -v n="$wanted_container" '$1 == n {print $2}')
    if [[ -z "$image" ]]
    then
      logerror "❌ $mq_kind $wanted_container is not running"
      return 1
    fi
    mq_container="$wanted_container"
    if [[ -n "$wanted_broker" ]]
    then
      mq_broker="$wanted_broker"
      return 0
    fi
    mq_broker=$(mq_broker_from_name "$image" || mq_broker_from_name "$mq_container") || {
      logerror "❌ could not tell the broker of $mq_container (image $image): pass --broker ($MQ_SUPPORTED_BROKERS)"
      return 1
    }
    return 0
  fi
  local candidates=()
  while IFS=$'\t' read -r name image
  do
    [[ -z "$name" ]] && continue
    broker=$(mq_broker_from_name "$image" || mq_broker_from_name "$name") || continue
    if [[ -n "$wanted_broker" && "$broker" != "$wanted_broker" ]]
    then
      continue
    fi
    candidates+=("$name:$broker")
  done < <(mq_list_running)
  if [[ ${#candidates[@]} -eq 0 ]]
  then
    logerror "❌ no running ${wanted_broker:-message broker} $mq_kind found (supported: $MQ_SUPPORTED_BROKERS)"
    logerror "   🎓 start an example with a broker, or pass --container (and --broker if the image name does not tell it)"
    return 1
  fi
  if [[ ${#candidates[@]} -gt 1 ]]
  then
    logerror "❌ several broker ${mq_kind}s are running, pass --container with one of them:"
    printf '   %s\n' "${candidates[@]}" | sed 's/:/ (/;s/$/)/' >&2
    return 1
  fi
  mq_container="${candidates[0]%%:*}"
  mq_broker="${candidates[0]##*:}"
}

# sets mq_user, mq_password and mq_qmgr / mq_vhost / mq_vpn from the container environment and the defaults of the
# examples, unless given: mq_resolve_credentials <user> <password>
function mq_resolve_credentials () {
  local user="$1" password="$2"
  mq_qmgr="" mq_vhost="${mq_vhost:-/}" mq_vpn="${mq_vpn:-default}"
  case "$mq_broker" in
    ibmmq)
      # local bindings in the container (amqsput, amqsbcg, runmqsc): no user needed
      mq_qmgr=$(mq_container_env MQ_QMGR_NAME)
      mq_qmgr="${mq_qmgr:-QM1}"
      mq_user="${user:-app}"
      mq_password="${password:-$(mq_container_env MQ_APP_PASSWORD)}"
    ;;
    rabbitmq)
      mq_user="${user:-$(mq_container_env RABBITMQ_DEFAULT_USER)}"
      mq_password="${password:-$(mq_container_env RABBITMQ_DEFAULT_PASS)}"
      mq_user="${mq_user:-guest}"
      mq_password="${mq_password:-guest}"
    ;;
    mqtt)
      # the password file of the MQTT examples
      mq_user="${user:-myuser}"
      mq_password="${password:-mypassword}"
    ;;
    activemq)
      mq_user="${user:-$(mq_container_env ACTIVEMQ_ADMIN_LOGIN)}"
      mq_password="${password:-$(mq_container_env ACTIVEMQ_ADMIN_PASSWORD)}"
      mq_user="${mq_user:-admin}"
      mq_password="${mq_password:-admin}"
    ;;
    solace)
      mq_user="${user:-admin}"
      mq_password="${password:-$(mq_container_env username_admin_password)}"
      mq_password="${mq_password:-admin}"
    ;;
  esac
}

function mq_describe () {
  case "$mq_broker" in
    ibmmq) echo "$mq_container, IBM MQ queue manager $mq_qmgr" ;;
    rabbitmq) echo "$mq_container, RabbitMQ vhost $mq_vhost, user $mq_user" ;;
    mqtt) echo "$mq_container, MQTT (mosquitto), user $mq_user" ;;
    activemq) echo "$mq_container, ActiveMQ, user $mq_user" ;;
    solace) echo "$mq_container, Solace message VPN $mq_vpn" ;;
  esac
}

# MQTT: checks the login before publishing or subscribing (mosquitto_pub -l retries a refused connection forever):
# a 1 second subscription to $SYS/broker/version, exit code 5 when the broker refuses the user or password
function mq_mqtt_check_login () {
  local out rc=0
  out=$(mq_exec mosquitto_sub -h localhost -p 1883 -u "$mq_user" -P "$mq_password" -t '$SYS/broker/version' -C 1 -W 1 < /dev/null 2>&1) || rc=$?
  # 27: timeout of -W ($SYS disabled): the login worked
  if [[ $rc -ne 0 && $rc -ne 27 ]]
  then
    logerror "❌ mosquitto refused the connection of user $mq_user: $(tail -1 <<< "$out")"
    logerror "   🔐 pass --user / --password (myuser / mypassword in the MQTT examples)"
    return 1
  fi
}

# checks the destination flags for the broker: mq_check_destination <queue> <topic> <operation>
# sets mq_dest_type (queue|topic) and mq_dest
function mq_check_destination () {
  local queue="$1" topic="$2" operation="$3"
  if [[ -n "$queue" ]]
  then
    mq_dest_type="queue"
    mq_dest="$queue"
  else
    mq_dest_type="topic"
    mq_dest="$topic"
  fi
  if [[ -z "$mq_dest" ]]
  then
    logerror "❌ pass --queue or --topic"
    return 1
  fi
  case "$mq_broker:$mq_dest_type" in
    mqtt:queue)
      logerror "❌ MQTT has no queue: pass --topic"
      return 1
    ;;
    rabbitmq:topic)
      logerror "❌ with RabbitMQ, pass --queue (messages are published to the queue through the default exchange)"
      return 1
    ;;
    ibmmq:topic|activemq:topic|solace:topic)
      if [[ "$operation" != "put" ]]
      then
        logerror "❌ a topic of $mq_broker keeps no message to $operation: pass --queue (or the queue subscribed to the topic)"
        return 1
      fi
    ;;
  esac
}

# runs curl in a container that shares the network namespace of the broker: localhost is the broker (docker only)
# on cfk, the curl of the broker image itself (the ActiveMQ and Solace images have one)
function mq_curl () {
  if [[ "$mq_transport" == "kubectl" ]]
  then
    if [[ "$mq_broker" == "activemq" || "$mq_broker" == "solace" ]]
    then
      kubectl -n confluent exec -i "$mq_container" -- curl -s -S "$@"
      return $?
    fi
    logerror "❌ the HTTP API of $mq_broker is not reachable from playground mq on cfk (its image has no curl)"
    return 1
  fi
  docker run --quiet --rm -i --network "container:$mq_container" "$MQ_CURL_IMAGE" -s -S "$@"
}

# RabbitMQ: rabbitmqadmin when the image has it (the -management images of the sink examples, docker or cfk), else
# the HTTP API from a curl container (docker only: the -alpine image has no curl and no rabbitmqadmin)
function mq_rabbitmq_has_admin () {
  mq_exec sh -c 'command -v rabbitmqadmin' > /dev/null 2>&1 < /dev/null
}

function mq_rabbitmq_admin () {
  mq_exec rabbitmqadmin -u "$mq_user" -p "$mq_password" -V "$mq_vhost" "$@" < /dev/null
}

# like mq_curl, the body written to the host file <out> and the http code printed: mq_curl_to_file <out> <curl args>
function mq_curl_to_file () {
  local out="$1" code
  shift
  mq_curl -w '\n%{http_code}' "$@" > "$out.tmp"
  code=$(tail -n 1 "$out.tmp")
  sed '$d' "$out.tmp" > "$out"
  rm -f "$out.tmp"
  echo "$code"
}

function mq_urlencode () {
  jq -rn --arg v "$1" '$v | @uri'
}

# RabbitMQ: the HTTP API of the management plugin, enabled on the fly when the image does not have it (the
# rabbitmq:*-alpine image of the source examples): rabbitmq-plugins enable rabbitmq_management
function mq_rabbitmq_api_ready () {
  if mq_curl -o /dev/null -f -u "$mq_user:$mq_password" "http://localhost:15672/api/overview" 2>/dev/null
  then
    return 0
  fi
  log "🔌 enabling the rabbitmq_management plugin in $mq_container (its HTTP API publishes and browses messages)"
  mq_exec rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1 < /dev/null || {
    logerror "❌ could not enable the rabbitmq_management plugin in $mq_container"
    return 1
  }
  local i
  for i in $(seq 1 30)
  do
    if mq_curl -o /dev/null -f -u "$mq_user:$mq_password" "http://localhost:15672/api/overview" 2>/dev/null
    then
      return 0
    fi
    sleep 1
  done
  logerror "❌ the HTTP API of rabbitmq_management did not answer on port 15672 of $mq_container (user $mq_user)"
  return 1
}

function mq_rabbitmq_queue_path () {
  echo "$(mq_urlencode "$mq_vhost")/$(mq_urlencode "$mq_dest")"
}

# current number of messages of a queue (0 when it does not exist yet), empty when it could not be read
function mq_depth () {
  local out
  case "$mq_broker" in
    ibmmq)
      out=$(echo "DISPLAY QLOCAL('$mq_dest') CURDEPTH" | mq_exec runmqsc "$mq_qmgr" 2>&1)
      if grep -q "AMQ8147E\|not found" <<< "$out"
      then
        echo 0
        return 0
      fi
      grep -o 'CURDEPTH([0-9]*)' <<< "$out" | head -1 | tr -dc '0-9'
    ;;
    rabbitmq)
      out=$(mq_exec rabbitmqctl -q list_queues -p "$mq_vhost" name messages 2>/dev/null < /dev/null) || return 0
      awk -v q="$mq_dest" -F'\t' '$1 == q {print $2; found=1} END {if (!found) print 0}' <<< "$out"
    ;;
    activemq)
      out=$(mq_curl -u "$mq_user:$mq_password" "http://localhost:8161/admin/xml/queues.jsp" 2>/dev/null) || return 0
      [[ -z "$out" ]] && return 0
      python3 -I -c 'if True:
        import re, sys
        xml, name = sys.stdin.read(), sys.argv[1]
        for m in re.finditer(r"<queue name=\"([^\"]*)\">(.*?)</queue>", xml, re.S):
            if m.group(1) == name:
                s = re.search(r"size=\"(\d+)\"", m.group(2))
                print(s.group(1) if s else 0)
                break
        else:
            print(0)' "$mq_dest" <<< "$out"
    ;;
    solace)
      out=$(mq_curl -u "$mq_user:$mq_password" "http://localhost:8080/SEMP/v2/monitor/msgVpns/$(mq_urlencode "$mq_vpn")/queues/$(mq_urlencode "$mq_dest")/msgs?count=1000&select=msgId" 2>/dev/null) || return 0
      if jq -e '.meta.error.code' <<< "$out" > /dev/null 2>&1
      then
        if jq -e '(.meta.error.description // "") | test("No queue named")' <<< "$out" > /dev/null 2>&1
        then
          echo 0
        fi
        return 0
      fi
      jq -r '.data | length' <<< "$out" 2>/dev/null
    ;;
  esac
}
