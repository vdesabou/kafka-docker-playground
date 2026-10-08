get_environment_used

log "💀 kill all docker containers (this also removes volumes)"
if [[ "$environment" == "cfk" ]]
then
	log "💀 stop local kubectl port-forward in confluent namespace"
	pkill -f "kubectl -n confluent port-forward" > /dev/null 2>&1 || true
	pkill -f "kubectl .*--namespace[= ]confluent.*port-forward" > /dev/null 2>&1 || true
	log "💀 delete all pods in confluent namespace"
	# don't wait for the 30s termination grace period: start-environment resets the namespace anyway
	kubectl -n confluent delete pod --all --grace-period=0 --force --wait=false
else
	docker rm -f $(docker ps -qa) > /dev/null 2>&1
	docker volume prune -f > /dev/null 2>&1
fi