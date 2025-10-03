verbose=${args[--verbose]}

get_connect_url_and_security

log "👨‍🔬 Discover connectors in the local connect cluster and export their configurations to files"
log "🛠️ It is using Connector Migration Utility (see https://github.com/confluentinc/connect-migration-utility/) on running connect cluster"

log "🔌 boostrapping ccloud environment"
bootstrap_ccloud_environment "" "" "true"

get_ccloud_connect

discovery_output_dir="$root_folder/connect-migration-utility-discovery-output"
rm -rf "$discovery_output_dir"

set +e
docker pull vdesabou/docker-connect-migration-utility:latest > /dev/null 2>&1
docker run -i --rm --network=host -v "$discovery_output_dir:/discovery_output_dir" vdesabou/docker-connect-migration-utility:latest bash -c "python src/discovery_script.py --worker-urls 'http://localhost:8083' --output-dir /discovery_output_dir --disable-ssl-verify --environment-id $environment --cluster-id $cluster" > /tmp/output.log 2>&1
ret=$?
set -e

if [[ -n "$verbose" ]]
then
  log "🐞 --verbose is set, full output of the discovery process:"
  cat /tmp/output.log
fi

if [ $ret -ne 0 ]
then
	logerror "❌ Failed to Run Kafka Connector Migration Utility, check output below:"
	cat /tmp/output.log
	exit 1
fi

if [ ! -f "$discovery_output_dir/summary.txt" ]
then
	logerror "❌ File "$discovery_output_dir/summary.txt" does not exist"
	exit 1
fi

log "📝 Summary of the discovery process:"
cat "$discovery_output_dir/summary.txt"

echo ""

json_count=$(find "$discovery_output_dir/discovered_configs/successful_configs/fm_configs" -name "*.json" -type f | wc -l)
if [ "$json_count" -eq 0 ]
then
	logerror "❌ No connector was discovered that can be migrated to fully managed"
	exit 1
else
	log "📁 Found $json_count connector configuration(s) that can be migrated to fully managed:"
	# Display the directory structure
	if command -v tree >/dev/null 2>&1; then
		tree "$discovery_output_dir/discovered_configs/successful_configs/fm_configs"
	else
		find "$discovery_output_dir/discovered_configs/successful_configs/fm_configs" -type f -name "*.json" | sort
	fi
	
	echo ""
	
	# Display each JSON file with its connector name
	for json_file in "$discovery_output_dir/discovered_configs/successful_configs/fm_configs"/*.json
	do
		if [ -f "$json_file" ]
		then
			log "📄 $(basename "$json_file")"
			# if [[ $(type -f bat 2>&1) =~ "not found" ]]
			# then
			# 	cat $json_file
			# else
			# 	bat $json_file
			# fi
			cat $json_file
		fi
	done

	log "✅ Now you can run 'playground connector connect-migration-utility migrate' to migrate these connectors to fully managed"
fi