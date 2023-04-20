ret=$(get_security_broker "--consumer.config")

container=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

log "Display content of connect offsets topic, press crtl-c to stop..."
docker exec $container kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --property print.timestamp=true $security