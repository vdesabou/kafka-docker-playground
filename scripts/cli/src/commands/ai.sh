arguments="${args[arguments]}"

cd $root_folder

get_environment_used

# 🧞‍♂️ The playground MCP server is declared in .mcp.json at the root of this
# repository, so it is offered to anybody running claude here. Claude Code asks
# for approval once per project before it starts a server found in .mcp.json;
# running `playground ai` is that approval, so record it (with the read-only
# tool permissions) in .claude/settings.local.json, which is not versioned.
if [ -f "$root_folder/.mcp.json" ]
then
    log "🧞‍♂️ mcp-playground server is used (see https://github.com/vdesabou/kafka-docker-playground-mcp-server) to inspect this playground: containers, connectors, logs and examples"
    mkdir -p "$root_folder/.claude"
    claude_settings="$root_folder/.claude/settings.local.json"
    if [ ! -s "$claude_settings" ]
    then
        echo '{}' > "$claude_settings"
    fi
    tmp_claude_settings=$(mktemp)
    if jq '
        .enabledMcpjsonServers = ((.enabledMcpjsonServers // []) + ["mcp-playground"] | unique)
        | .permissions.allow = ((.permissions.allow // []) + [
            "mcp__mcp-playground__playground_status",
            "mcp__mcp-playground__playground_connectors",
            "mcp__mcp-playground__playground_logs",
            "mcp__mcp-playground__playground_find_example",
            "mcp__mcp-playground__playground_example_details"
          ] | unique)
    ' "$claude_settings" > "$tmp_claude_settings"
    then
        mv "$tmp_claude_settings" "$claude_settings"
    else
        rm -f "$tmp_claude_settings"
        logwarn "⚠️ could not update $claude_settings, claude will ask to approve the mcp-playground server"
    fi

    # npx clones and builds the server on first use, which can take longer than
    # claude waits for an MCP server to come up. Run it once here with no stdin
    # so that it fills the npx cache and exits immediately, instead of timing
    # out inside claude with an unhelpful "Failed to reconnect".
    mcp_playground_command=$(jq -r '.mcpServers."mcp-playground" | ([.command] + .args) | @sh' "$root_folder/.mcp.json" 2>/dev/null)
    if [ -n "$mcp_playground_command" ]
    then
        set +e
        eval "$mcp_playground_command" < /dev/null > /dev/null 2>&1
        set -e
    fi
fi

if [[ "$environment" == "ccloud" ]]
then
    if [ -f .ccloud/.env ]
    then
        log "🌩️ ccloud environment is used, using mcp-confluent server (https://docs.confluent.io/cloud/current/ai/ai-tools/open-source-mcp-server.html) to interact with confluent cloud"
        claude mcp remove mcp-kafka > /dev/null 2>&1 || true
        claude mcp remove mcp-ccloud > /dev/null 2>&1 || true
        cd $root_folder > /dev/null
        source .ccloud/.env
        # generate data file for mcp-confluent
        sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
            -e "s|:KAFKA_API_KEY:|$KAFKA_API_KEY|g" \
            -e "s|:KAFKA_API_SECRET:|$KAFKA_API_SECRET|g" \
            -e "s|:KAFKA_REST_ENDPOINT:|$KAFKA_REST_ENDPOINT|g" \
            -e "s|:KAFKA_CLUSTER_ID:|$KAFKA_CLUSTER_ID|g" \
            -e "s|:KAFKA_ENV_ID:|$KAFKA_ENV_ID|g" \
            -e "s|:SCHEMA_REGISTRY_ENDPOINT:|$SCHEMA_REGISTRY_ENDPOINT|g" \
            -e "s|:SCHEMA_REGISTRY_API_KEY:|$SCHEMA_REGISTRY_API_KEY|g" \
            -e "s|:SCHEMA_REGISTRY_API_SECRET:|$SCHEMA_REGISTRY_API_SECRET|g" \
            -e "s|:CONFLUENT_CLOUD_REST_ENDPOINT:|$CONFLUENT_CLOUD_REST_ENDPOINT|g" \
            -e "s|:CONFLUENT_CLOUD_API_KEY:|$CONFLUENT_CLOUD_API_KEY|g" \
            -e "s|:CONFLUENT_CLOUD_API_SECRET:|$CONFLUENT_CLOUD_API_SECRET|g" \
            $root_folder/scripts/cli/src/mcp-confluent-config-ccloud-template.yaml > $root_folder/config.yaml

        # --registry: the packages are public, so do not go through a private
        # registry the user may be logged out of (npm ERR! E401 would make the
        # server exit at startup, and claude only reports "Failed to reconnect").
        claude mcp add mcp-ccloud -- npx --registry=https://registry.npmjs.org -y @confluentinc/mcp-confluent --config ./config.yaml
        cd - > /dev/null
    else
        logerror "❌ .ccloud/.env file is not present!"
        exit 1
    fi
else
    claude mcp remove mcp-ccloud > /dev/null 2>&1 || true

    if [[ "$environment" == "plaintext" ]]
    then
        log "📭 plaintext environment is used, using mcp-confluent server (https://docs.confluent.io/cloud/current/ai/ai-tools/open-source-mcp-server.html) to interact with the cluster"
        claude mcp remove mcp-kafka > /dev/null 2>&1 || true
        cd $root_folder > /dev/null
        cp $root_folder/scripts/cli/src/mcp-confluent-config-local.yaml config.yaml
        claude mcp add mcp-kafka -- npx --registry=https://registry.npmjs.org -y @confluentinc/mcp-confluent --config ./config.yaml
        cd - > /dev/null
    else
        logwarn "🔐 $environment environment is used, using mcp-confluent server (https://docs.confluent.io/cloud/current/ai/ai-tools/open-source-mcp-server.html) to interact with the cluster will not be used, only works with plaintext for now"
    fi
fi

log "consider using confluent agent skills (see https://docs.confluent.io/cloud/current/ai/ai-tools/agent-skills.html)"

log "🧞‍♂️ calling claude cli: claude ${other_args[*]}"
claude "${other_args[*]}"