containers="${args[--container]}"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	if [[ "$container" == "connect" ]] || [[ "$container" == "broker" ]]
	then
		log "⛑️ Creating diagnostics bundle for container ${container}"
		log "⏳ please wait..."
	else
		logerror "❌ only connect and broker containers are supported"
		exit 1
	fi

	docker exec $container curl -L https://packages.confluent.io/tools/diagnostics-bundle/diagnostics-bundle-1.0.0.jar -o /tmp/diagnostics-bundle-1.0.0.jar > /dev/null 2>&1

	fifo_path="$tmp_dir/collect_fifo"
	mkfifo "$fifo_path"

	set +e
	docker exec $container java -jar /tmp/diagnostics-bundle-1.0.0.jar collect > "$fifo_path" 2>&1 &

	# Loop through each line in the named pipe
	while read -r line
	do
		echo "$line"
		echo "$line" >> $tmp_dir/result.log

	done < "$fifo_path"

	nb=$(grep -c "Diagnostics output has been zipped and written to" $tmp_dir/result.log)
	if [ $nb -eq 0 ]
	then
		logerror "❌ Failed to generate bundle"
		cat $tmp_dir/result.log
		exit 1
	fi
	bundle_file=$(cat $tmp_dir/result.log | grep "Diagnostics output has been zipped and written to" | cut -d ":" -f 4 | sed 's/ //g')
	bundle_file_filename=$(basename -- "$bundle_file")
	log "⛑️ diagnostics bundle is available at ${bundle_file_filename}"
	docker cp ${container}:${bundle_file} ${bundle_file_filename}
done