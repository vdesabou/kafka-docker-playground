arguments="${args[arguments]}"

cd $root_folder

get_environment_used

set +e
docker pull vdesabou/mcp-playground-server:latest > /dev/null 2>&1
set +e

if [[ "$environment" == "ccloud" ]]
then
	if [ -f .ccloud/.env ]
	then
		log "🌩️ ccloud environment is used, using mcp-confluent server (https://github.com/confluentinc/mcp-confluent) to interact with confluent cloud"
		gemini mcp remove mcp-kafka > /dev/null 2>&1 || true
		gemini mcp remove mcp-ccloud > /dev/null 2>&1 || true
		gemini mcp add --trust mcp-ccloud npx "-y" "@confluentinc/mcp-confluent@latest" -- "-e" "$root_folder/.ccloud/.env"
	else
		logerror "❌ .ccloud/.env file is not present!"
		exit 1
	fi
else
	# https://github.com/google-gemini/gemini-cli/issues/9766
	gemini mcp remove mcp-ccloud > /dev/null 2>&1 || true

	if [[ "$environment" == "plaintext" ]]
	then
		log "🌩️ plaintext environment is used, using kafka-mcp-server (https://docs.tuannvm.com/kafka-mcp-server) to interact with the cluster"
		gemini mcp remove mcp-kafka > /dev/null 2>&1 || true
		gemini mcp add --trust mcp-kafka kafka-mcp-server -e "KAFKA_BROKERS=localhost:29092" -e "KAFKA_CLIENT_ID=kafka-mcp-server" -e "MCP_TRANSPORT=stdio"
	else
		logwarn "🔐 $environment environment is used, using kafka-mcp-server (https://docs.tuannvm.com/kafka-mcp-server) to interact with the cluster will not be used, only works with plaintext for now"
	fi
fi

log "🧞‍♂️ calling gemini cli: gemini ${other_args[*]}"
gemini "${other_args[*]}"