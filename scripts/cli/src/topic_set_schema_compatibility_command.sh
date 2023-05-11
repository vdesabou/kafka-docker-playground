topic="${args[--topic]}"
compatibility="${args[--compatibility]}"

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

log "🛡️ Set compatibility for subject ${topic}-value to $compatibility"
curl $sr_security -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"compatibility\": \"$compatibility\"}" "${sr_url}/config/${topic}-value"