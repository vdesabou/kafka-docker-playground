get_environment_used

log "💀 kill all docker containers (this also removes volumes)"
if [[ "$environment" == cfk* ]]
then
	log "💀 stop local kubectl port-forward in confluent namespace"
	pkill -f "kubectl -n confluent port-forward" > /dev/null 2>&1 || true
	pkill -f "kubectl .*--namespace[= ]confluent.*port-forward" > /dev/null 2>&1 || true
	log "💀 delete all pods in confluent namespace (except the CFK operator, kept between runs)"
	pods=$(kubectl -n confluent get pods -l 'app!=confluent-operator' --no-headers -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' 2>/dev/null)
	if [ -n "$pods" ]
	then
		echo "$pods" | while read -r name pod_status
		do
			log "   ☠️  $name ($pod_status)"
		done
	fi
	# don't wait for the 30s termination grace period: start-environment resets the namespace anyway
	kubectl -n confluent delete pod -l 'app!=confluent-operator' --grace-period=0 --force --wait=false
else
	containers=$(docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null)
	if [ -z "$containers" ]
	then
		log "🤷 no container to kill"
	else
		log "💀 $(echo "$containers" | wc -l | tr -d ' ') container(s) to kill:"
		echo "$containers" | while IFS='|' read -r name image container_status
		do
			log "   ☠️  $name ($image, $container_status)"
		done
		docker rm -f $(docker ps -qa) > /dev/null 2>&1
	fi
	docker volume prune -f > /dev/null 2>&1
fi
