arguments="${args[arguments]}"

log "🔐 Testing TLS/SSL encryption with arguments $arguments"
docker run --rm -ti  drwetter/testssl.sh $arguments