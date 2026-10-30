file="${args[file]}"
verbose="${args[--verbose]}"
connector="${args[--connector]}"
to="${args[--to]}"
from="${args[--from]}"
name="${args[--name]}"
no_adapt="${args[--no-adapt]}"
json="${args[--json]}"
secrets_as_variables="${args[--secrets-as-variables]}"

if [ "$file" = "-" ]
then
    content=$(read_stdin_if_any)
    if [ -z "${content//[[:space:]]/}" ]
    then
        logerror "❌ no connector config: give the path of a file, or pipe it on stdin"
        exit 1
    fi
elif [ -f "${file#@}" ]
then
    content=$(cat "${file#@}")
else
    logerror "❌ file ${file#@} not found"
    exit 1
fi

# the findings go to stderr, the converted config to stdout
if ! normalize_connector_config "$content" "$connector" "$from"
then
    logerror "❌ $NORMALIZED_ERROR" >&2
    exit 1
fi
log "📦 detected: $NORMALIZED_FORMAT" >&2
config="$NORMALIZED_CONFIG"
name=${name:-${NORMALIZED_NAME:-${connector:-my-connector}}}
config=$(echo "$config" | jq --arg name "$name" '.name = $name')

if [[ -z "$no_adapt" ]] && { [ "$to" == "heredoc" ] || [ "$to" == "json" ]; }
then
    connector_config_adapt "$config" report >&2
    config="$ADAPTED_CONFIG"
fi
connector_config_findings "$config" >&2
placeholders=$(connector_config_placeholders "$config")

# keys whose value is a secret, for terraform config_sensitive
secret_keys_regex='(password|secret|jaas|token|credential|api[._]key|private[._]key|keystore\.key|access[._]key|user\.info)'

if [[ -n "$secrets_as_variables" ]]
then
    # the secrets written as they are, so that the heredoc can go in a script that is committed: the settings next to
    # them (basic.auth.credentials.source, *.mechanism…), values already masked or read from a file of the examples stay
    secrets=$(echo "$config" | jq -r --arg secret_regex "$secret_keys_regex" --arg already "$(echo "$placeholders" | cut -d'|' -f1)" '
        ($already | split("\n")) as $listed
        | to_entries[]
        | select(.key | test($secret_regex; "i"))
        | select(.key | test("\\.(source|mechanism|protocol|type|class|location|enabled|algorithm|path|file)$"; "i") | not)
        | select((.value | type) == "string" and .value != "" and (.value | test("^\\$\\{") | not))
        | select(.key as $k | $listed | index($k) | not)
        | "\(.key)|secret value of the customer, kept out of the script"')
    if [ -n "$secrets" ]
    then
        log "🔐 $(echo "$secrets" | grep -c .) secret value(s) replaced with variables: $(echo "$secrets" | cut -d'|' -f1 | paste -sd ' ' -)" >&2
        placeholders=$(printf '%s\n%s' "$placeholders" "$secrets" | grep .)
    fi
fi

if [[ -n "$json" ]]
then
    jq -n --arg format "$NORMALIZED_FORMAT" --arg name "$name" --argjson config "$config" --arg placeholders "$placeholders" '{
        detected_format: $format,
        name: $name,
        config: $config,
        to_fill_in: ($placeholders | split("\n") | map(select(length > 0) | split("|") | {key: .[0], reason: (.[1:] | join("|"))}))
    }'
    exit 0
fi

case "$to" in
    json)
        echo "$config" | jq .
        ;;
    heredoc)
        if [ -z "$placeholders" ]
        then
            echo "playground connector create-or-update --connector $name << 'EOF'"
            echo "$config" | jq .
            echo "EOF"
        else
            # the values to fill in become variables (AWS_SECRET_ACCESS_KEY for aws.secret.access.key), so the heredoc is
            # not quoted: every other $ is escaped
            echo "# values to fill in before running it:"
            echo "$placeholders" | awk -F'|' '{ v = toupper($1); gsub(/[^A-Z0-9]/, "_", v); printf "#   export %s=...   # %s: %s\n", v, $1, $2 }'
            echo "playground connector create-or-update --connector $name << EOF"
            echo "$config" | jq --arg keys "$(echo "$placeholders" | cut -d'|' -f1)" '
                ($keys | split("\n") | map(select(length > 0))) as $to_fill
                | with_entries(
                    if (.key as $k | $to_fill | index($k)) then .value = "${\(.key | ascii_upcase | gsub("[^A-Z0-9]"; "_"))}"
                    else .value |= gsub("\\$"; "\\$") end)' \
                | sed -E 's/"\$\{([A-Z0-9_]+)\}"/"${\1}"/; s/\\\\\$/\\$/g'
            echo "EOF"
        fi
        ;;
    properties)
        echo "# connector $name, converted by playground connector convert from a $NORMALIZED_FORMAT"
        # java.util.Properties escapes: backslashes, and in keys the separators
        echo "$config" | jq -r 'to_entries[]
            | (.key | gsub("\\\\"; "\\\\") | gsub("(?<c>[=: ])"; "\\\(.c)")) as $k
            | (.value | gsub("\\\\"; "\\\\") | gsub("\n"; "\\n") | sub("^ "; "\\ ")) as $v
            | "\($k)=\($v)"'
        ;;
    cfk)
        echo "$config" | jq --arg name "$name" '{
            apiVersion: "platform.confluent.io/v1beta1",
            kind: "Connector",
            metadata: {name: $name, namespace: "confluent"},
            spec: {
                class: (."connector.class" // ""),
                taskMax: ((."tasks.max" // "1") | tonumber? // 1),
                connectClusterRef: {name: "connect"},
                configs: (del(."connector.class", ."tasks.max", .name))
            }
        }' | yq -p json -o yaml -P '.'
        ;;
    strimzi)
        echo "$config" | jq --arg name "$name" '{
            apiVersion: "kafka.strimzi.io/v1beta2",
            kind: "KafkaConnector",
            metadata: {name: $name, labels: {"strimzi.io/cluster": "my-connect-cluster"}},
            spec: {
                class: (."connector.class" // ""),
                tasksMax: ((."tasks.max" // "1") | tonumber? // 1),
                config: (del(."connector.class", ."tasks.max", .name))
            }
        }' | yq -p json -o yaml -P '.'
        ;;
    terraform)
        if [[ "$(echo "$config" | jq -r '."connector.class" // ""')" == *.* ]]
        then
            logwarn "⚠️ terraform confluent_connector manages fully managed connectors: $(echo "$config" | jq -r '."connector.class"') is a self-managed class, translate the config first (playground connector translate)" >&2
        fi
        echo "$config" | jq -r --arg name "$name" --arg secret_regex "$secret_keys_regex" '
            # an hcl string: backslashes, quotes, and ${ / %{ that would be interpolated
            def hcl: "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n") | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{")) + "\"";
            def block($entries): ($entries | map(.key | length) | max // 0) as $width
                | $entries | map("    \(.key | hcl)\(" " * ($width - (.key | length))) = \(.value | hcl)") | join("\n");
            (to_entries | map(select(.key | test($secret_regex; "i")))) as $sensitive
            | (to_entries | map(select(.key | test($secret_regex; "i") | not))) as $nonsensitive
            | "resource \"confluent_connector\" \"\($name | gsub("[^A-Za-z0-9_-]"; "_"))\" {",
              "  environment {",
              "    id = var.environment_id",
              "  }",
              "  kafka_cluster {",
              "    id = var.kafka_cluster_id",
              "  }",
              (if ($sensitive | length) > 0 then "  config_sensitive = {", block($sensitive), "  }" else empty end),
              "  config_nonsensitive = {",
              block($nonsensitive),
              "  }",
              "}"'
        ;;
esac
