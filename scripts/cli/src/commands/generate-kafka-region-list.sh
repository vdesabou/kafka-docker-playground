confluent kafka region list | awk -F'|' '{print $1"/"$3}' | sed 's/[[:blank:]]//g' | grep -v "CloudID" | grep -v "\-\-\-" | grep -v '^/' > $root_folder/scripts/cli/confluent-kafka-region-list.txt
