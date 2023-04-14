security_broker=$(get_security_broker)

log "Display content of connect offsets topic, press crtl-c to stop..."
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --property print.timestamp=true $security_broker