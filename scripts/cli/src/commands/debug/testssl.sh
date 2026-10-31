uri="${args[--uri]}"

# -ti only with a terminal (docker refuses -t in scripts and CI)
tty_flags=()
if [ -t 0 ] && [ -t 1 ]
then
	tty_flags=(-ti)
fi

if [[ ${#other_args[@]} -gt 0 ]]
then
	log "🔐 Testing TLS/SSL encryption with uri $uri and arguments ${other_args[*]}"
	docker run --quiet --rm "${tty_flags[@]}" drwetter/testssl.sh "${other_args[@]}" "$uri"
else
	log "🔐 Testing TLS/SSL encryption with uri $uri"
	docker run --quiet --rm "${tty_flags[@]}" drwetter/testssl.sh "$uri"
fi
