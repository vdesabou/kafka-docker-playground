containers="${args[--container]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
	log "📝 Displaying properties file for $container"

docker exec -i "$container" sh << EOF
ps -ef | grep properties | grep java | grep -v grep | awk '{ print \$NF }' > /tmp/propertie_file
propertie_file=\$(cat /tmp/propertie_file)
if [ ! -f \$propertie_file ]
then
  logerror 'ERROR: Could not determine properties file!'
  exit 1
fi
cat \$propertie_file | grep -v None | grep .
EOF
done

