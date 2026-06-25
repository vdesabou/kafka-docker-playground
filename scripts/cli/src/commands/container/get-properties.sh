containers="${args[--container]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
  resolved_container=$(resolve_container_name_for_environment "$container")
	log "📝 Displaying properties file for $container"

if [[ "$environment" == "cfk" ]]
then
kubectl -n confluent exec -i "$resolved_container" -- sh << EOF
ps -ef | grep properties | grep java | grep -v grep | awk '{ print \$NF }' > /tmp/propertie_file
propertie_file=\$(cat /tmp/propertie_file)
if [ ! -f \$propertie_file ]
then
  echo 'ERROR: Could not determine properties file!'
  exit 1
fi
cat \$propertie_file | grep -v None | grep .
EOF
else
docker exec -i "$resolved_container" sh << EOF
ps -ef | grep properties | grep java | grep -v grep | awk '{ print \$NF }' > /tmp/propertie_file
propertie_file=\$(cat /tmp/propertie_file)
if [ ! -f \$propertie_file ]
then
  logerror 'ERROR: Could not determine properties file!'
  exit 1
fi
cat \$propertie_file | grep -v None | grep .
EOF
fi
done

