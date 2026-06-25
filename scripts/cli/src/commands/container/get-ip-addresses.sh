get_environment_used

log "Get IP address of running containers"
if [[ "$environment" == "cfk" ]]
then
	kubectl -n confluent get pods -o wide | awk 'NR==1 || $6!="" {print $1 " - " $6}'
else
	docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq)
fi