#docker exec broker kafka-topics --bootstrap-server broker:9092 --list | grep -v "^_"
# trick to be faster
docker exec broker ls /var/lib/kafka/data | grep -v "checkpoint" | grep -v "meta.properties" | grep -v "^_" | sed 's/[^-]*$//' | sed 's/.$//' | sort | uniq