arguments="${args[arguments]}"
yolo="${args[--yolo]}"

cd $root_folder

get_environment_used

set +e
docker pull vdesabou/mcp-playground-server:latest > /dev/null 2>&1
set +e

if [[ "$environment" == "ccloud" ]]
then
	if [ -f .ccloud/.env ]
	then
		log "🌩️ ccloud environment is used, using mcp-confluent server to interact with confluent cloud"
		gemini mcp remove mcp-confluent > /dev/null 2>&1 || true
		gemini mcp add mcp-confluent npx "-y" "@confluentinc/mcp-confluent@latest" -- "-e" "$root_folder/.ccloud/.env"
	else
		logerror "❌ .ccloud/.env file is not present!"
		exit 1
	fi
else
	# https://github.com/google-gemini/gemini-cli/issues/9766
	gemini mcp remove mcp-confluent > /dev/null 2>&1 || true
fi

if [[ -n "$yolo" ]]
then
	log "🧞‍♂️🤟 calling gemini cli in yolo mode: gemini ${other_args[*]}"
	gemini --approval-mode=yolo "${other_args[*]}"
else
	log "🧞‍♂️ calling gemini cli: gemini ${other_args[*]}"
	gemini "${other_args[*]}"
fi
