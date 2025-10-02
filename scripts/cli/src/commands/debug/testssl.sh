uri="${args[--uri]}"


if [[ ${#other_args[@]} -gt 0 ]]
then
	log "🔐 Testing TLS/SSL encryption with uri $uri and arguments ${other_args[*]}"
	docker run --quiet --rm -ti  drwetter/testssl.sh "${other_args[*]}" "$uri"
else
	log "🔐 Testing TLS/SSL encryption with uri $uri"
	docker run --quiet --rm -ti  drwetter/testssl.sh "$uri"
fi
