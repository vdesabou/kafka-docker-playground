hostname="${args[--hostname]}"
port="${args[--port]}"
throttle_service_response="${args[--throttle-service-response]}"
delay_service_response="${args[--delay-service-response]}"
break_service_response="${args[--break-service-response]}"
service_response_corrupt="${args[--service-response-corrupt]}"
skip_automatic_connector_config=${args[--skip-automatic-connector-config]}

# keep TAG, CONNECT TAG and ORACLE_IMAGE
export TAG=$(docker inspect -f '{{.Config.Image}}' broker 2> /dev/null | cut -d ":" -f 2)
export CP_CONNECT_TAG=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
export ORACLE_IMAGE=$(docker inspect -f '{{.Config.Image}}' oracle 2> /dev/null)

docker_command=$(playground state get run.docker_command)
if [ "$docker_command" == "" ]
then
  logerror "docker_command retrieved from $root_folder/playground.ini is empty !"
  exit 1
fi

service_response_corrupt_method=""
if [[ -n "$service_response_corrupt" ]]
then
    service_response_corrupt_method="randomize"
fi

mkdir -p ${root_folder}/zazkia
  cat << EOF > ${root_folder}/zazkia/zazkia-routes.json
[
    {
        "label": "tcp-proxy",
        "service-hostname": "$hostname",
        "service-port": $port,
        "listen-port": 49998,
        "transport": {
            "accept-connections": true,
            "throttle-service-response": $throttle_service_response,
            "delay-service-response": $delay_service_response,
            "break-service-response": $break_service_response,
            "service-response-corrupt-method": "$service_response_corrupt_method",
            "sending-to-client": true,
            "receiving-from-client": true,
            "sending-to-service": true,
            "receiving-from-service": true,
            "verbose": true
        }
    }
]
EOF

  cat << EOF > /tmp/docker-compose.override.zazkia.yml
services:
  zazkia:
    hostname: zazkia
    container_name: zazkia
    # use my own image because of https://github.com/emicklei/zazkia/issues/4
    image: vdesabou/zazkia:latest
    ports:
      - "9191:9191"
    volumes:
      - ${root_folder}/zazkia:/data
    environment:
      DUMMY: $RANDOM
EOF

echo "$docker_command" > /tmp/playground-command-zazkia
sed -i -E -e "s|up -d --quiet-pull|-f /tmp/docker-compose.override.zazkia.yml up -d --quiet-pull|g" /tmp/playground-command-zazkia
log "💫 adding container zazkia listening on port 49998"
bash /tmp/playground-command-zazkia

log "💗 you can now use zazkia tcp proxy using <zazkia:49998>"
log "🌐 zazkia UI is available on http://localhost:9191"
if [[ $(type -f open 2>&1) =~ "not found" ]]
then
  :
else
  open "http://localhost:9191"
fi

if [[ -n "$skip_automatic_connector_config" ]]
then
    log "🤖 --skip-automatic-connector-config is set"
else
  connector=$(playground get-connector-list)
  if [ "$connector" == "" ]
  then
      log "💤 No connector is running, skipping automatic update of connector configuration with tcp proxy"
      exit 0
  fi

  tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
  if [ -z "$PG_VERBOSE_MODE" ]
  then
      trap 'rm -rf $tmp_dir' EXIT
  else
      log "🐛📂 not deleting tmp dir $tmp_dir"
  fi

  items=($connector)
  for connector in "${items[@]}"
  do
    is_modified=0
    log "🔮 checking existence of hostname $hostname and port $port in connector $connector configuration to replace with zazkia and port 49998" 
    playground --output-level ERROR connector show-config --connector $connector > "$tmp_dir/create-$connector-config.sh"

    if grep -q "$hostname:$port" "$tmp_dir/create-$connector-config.sh"; then
      sed -i -E -e "s|$hostname:$port|zazkia:49998|g" "$tmp_dir/create-$connector-config.sh"
      log "replacing $hostname:$port by zazkia:49998"
      is_modified=1
    fi

    if grep -q "\"$hostname\"" "$tmp_dir/create-$connector-config.sh"; then
      sed -i -E -e "s|\"$hostname\"|\"zazkia\"|g" "$tmp_dir/create-$connector-config.sh"
      log "replacing \"$hostname\" by \"zazkia\""
      is_modified=1
    fi
    if grep -q "$port" "$tmp_dir/create-$connector-config.sh"; then
      sed -i -E -e "s|$port|49998|g" "$tmp_dir/create-$connector-config.sh"
      log "replacing $port by 49998"
      is_modified=1
    fi

    if [ $is_modified -eq 1 ]
    then
      log "💫 updating connector $connector configuration with"
      cat "$tmp_dir/create-$connector-config.sh"
      check_if_continue
      bash "$tmp_dir/create-$connector-config.sh"
    else
      logwarn "💅 could not replace automatically hostname $hostname and port $port in connector $connector configuration, please do it manually !"
    fi
  done
fi