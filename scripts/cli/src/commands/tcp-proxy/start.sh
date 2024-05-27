hostname="${args[--hostname]}"
port="${args[--port]}"
throttle_service_response="${args[--throttle-service-response]}"
delay_service_response="${args[--delay-service-response]}"
break_service_response="${args[--break-service-response]}"
service_response_corrupt="${args[--service-response-corrupt]}"

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

mkdir -p /tmp/zazkia
  cat << EOF > /tmp/zazkia/zazkia-routes.json
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
    image: emicklei/zazkia
    ports:
      - "9191:9191"
    volumes:
      - /tmp/zazkia:/data
    environment:
      DUMMY: $RANDOM
EOF

echo "$docker_command" > /tmp/playground-command-zazkia
sed -i -E -e "s|up -d --quiet-pull|-f /tmp/docker-compose.override.zazkia.yml up -d --quiet-pull|g" /tmp/playground-command-zazkia
log "💫 adding container zazkia listening on port 49998"
bash /tmp/playground-command-zazkia

log "💗 you can now use tcp-proxy using <zazkia:49998>"
log "🌐 zazkia UI is available on http://localhost:9191"