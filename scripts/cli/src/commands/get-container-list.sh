get_environment_used

if [[ "$environment" == "cfk" ]]
then
  kubectl -n confluent get pods -o name 2>/dev/null | sed 's#pod/##'
else
  docker ps --format '{{.Names}}'
fi
