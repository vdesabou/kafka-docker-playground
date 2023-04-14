environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

sr_url="http://localhost:8081"
security_sr=""
if [ "$environment" != "plaintext" ]
then
    sr_url="https://localhost:8081"
    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

    security_certs="--cert $DIR_CLI/../../environment/$environment/security/schema-registry.certificate.pem --key $DIR_CLI/../../environment/$environment/security/schema-registry.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
fi

# Get a list of all subjects in the schema registry
subjects=$(curl $security_certs -s "${sr_url}/subjects")

log "Displaying all subjects 🔰 and versions 💯"
# Loop through each subject and retrieve all its schema versions and definitions
for subject in $(echo "${subjects}" | jq -r '.[]'); do
  # Get a list of all schema versions for the subject
  versions=$(curl $security_certs -s "${sr_url}/subjects/${subject}/versions")
  
  # Loop through each version and retrieve the schema
  for version in $(echo "${versions}" | jq -r '.[]'); do
    schema=$(curl $security_certs -s "${sr_url}/subjects/${subject}/versions/${version}/schema" | jq .)
    log "🔰 ${subject} 💯 ${version}"
    echo "${schema}"
  done
done