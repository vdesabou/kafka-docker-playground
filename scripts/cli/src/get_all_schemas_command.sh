ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

# Get a list of all subjects in the schema registry
subjects=$(curl $security -s "${sr_url}/subjects")

log "Displaying all subjects 🔰 and versions 💯"
# Loop through each subject and retrieve all its schema versions and definitions
for subject in $(echo "${subjects}" | jq -r '.[]'); do
  # Get a list of all schema versions for the subject
  versions=$(curl $security -s "${sr_url}/subjects/${subject}/versions")
  
  # Loop through each version and retrieve the schema
  for version in $(echo "${versions}" | jq -r '.[]'); do
    schema=$(curl $security -s "${sr_url}/subjects/${subject}/versions/${version}/schema" | jq .)
    log "🔰 ${subject} 💯 ${version}"
    echo "${schema}"
  done
done