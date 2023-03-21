container="${args[--container]}"
shell="${args[--shell]}"

docker exec -it "$container" "$shell"