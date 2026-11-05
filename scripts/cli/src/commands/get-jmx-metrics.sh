IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

containers="${args[--container]}"
domain="${args[--domain]}"
open="${args[--open]}"
# repeatable: the values are quoted by bashly (and a pattern holds a *: never let the shell expand it)
mbeans=""
if [[ -n "${args[--mbean]}" ]]
then
    eval "mbean_array=(${args[--mbean]})"
    mbeans="${mbean_array[*]}"
fi
all="${args[--all]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# the container names and their JMX port are checked by get_jmx_metrics
for container in "${container_array[@]}"
do
	get_jmx_metrics "$container" "$domain" "$open" "$mbeans" "$all" || exit 1
done
