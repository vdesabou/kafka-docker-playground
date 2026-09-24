set +e
run_kafka_admin_tool kafka-consumer-groups --list 2>/dev/null | grep -v "No configuration found" | sort
set -e
