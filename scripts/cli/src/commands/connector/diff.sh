connector="${args[--connector]}"
file="${args[--file]}"
with_connector="${args[--with-connector]}"
defaults="${args[--defaults]}"
json="${args[--json]}"
verbose="${args[--verbose]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"

connector_type=$(playground state get run.connector_type)

if [[ -z "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
    if [ $(echo "$connector" | wc -w) -gt 1 ]
    then
        logerror "❌ several connectors are running ($connector), use --connector"
        exit 1
    fi
fi

nb_sources=0
[[ -n "$file" ]] && nb_sources=$((nb_sources+1))
[[ -n "$with_connector" ]] && nb_sources=$((nb_sources+1))
[[ -n "$defaults" ]] && nb_sources=$((nb_sources+1))
if [ $nb_sources -gt 1 ]
then
    logerror "❌ set only one of --file, --with-connector, --defaults"
    exit 1
fi
stdin_content=""
if [ $nb_sources -eq 0 ]
then
    stdin_content=$(read_stdin_if_any)
    if [[ -z "$stdin_content" ]]
    then
        logerror "❌ nothing to compare with: give a config on stdin, or --file, --with-connector or --defaults"
        exit 1
    fi
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if ! get_connector_config_json "$connector"
then
    logerror "❌ could not get the config of connector $connector"
    exit 1
fi
echo "$curl_output" > $tmp_dir/a.json
label_a="$connector"

# a file or stdin can be a plain config, or a 'playground connector create-or-update' heredoc as printed by show-config
function read_config () {
    local content
    content=$(cat)
    if ! echo "$content" | jq -e 'type == "object"' > /dev/null 2>&1
    then
        content=$(echo "$content" | sed -n '/<< *.\{0,1\}EOF/,/^EOF/p' | sed '1d;$d' | sed 's/\\\$/$/g')
    fi
    if ! echo "$content" | jq -e 'type == "object"' > /dev/null 2>&1
    then
        logerror "❌ $1 is not a JSON connector config"
        exit 1
    fi
    # a full connector (REST API GET /connectors/<name>) has the config in .config
    echo "$content" | jq 'if (.config | type) == "object" and has("name") then .config else . end'
}

if [[ -n "$with_connector" ]]
then
    if ! get_connector_config_json "$with_connector"
    then
        logerror "❌ could not get the config of connector $with_connector"
        exit 1
    fi
    echo "$curl_output" > $tmp_dir/b.json
    label_b="$with_connector"
elif [[ -n "$file" ]]
then
    read_config "$file" < "$file" > $tmp_dir/b.json
    label_b="$(basename "$file")"
elif [[ -n "$defaults" ]]
then
    # default value of each parameter, from the validate endpoint of the plugin
    connector_class=$(jq -r '."connector.class"' $tmp_dir/a.json)
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$tmp_dir/a.json https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate"
    elif [[ "$(playground state get run.environment)" == cfk* ]]
    then
        logerror "❌ --defaults is not supported with CFK (no Connect REST validation endpoint)"
        exit 1
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$tmp_dir/a.json $connect_url/connector-plugins/$connector_class/config/validate"
    fi
    echo "$curl_output" | jq '[.configs[] | select(.definition != null) | {key: .definition.name, value: .definition.default_value}] | from_entries' > $tmp_dir/b.json 2> /dev/null || true
    if [ ! -s $tmp_dir/b.json ] || [ "$(jq length $tmp_dir/b.json)" == "0" ]
    then
        logerror "❌ the validate endpoint did not return the parameter definitions of $connector_class"
        exit 1
    fi
    label_b="defaults"
else
    echo "$stdin_content" | read_config "stdin" > $tmp_dir/b.json
    label_b="stdin"
fi

# masked values ("[hidden]", "****", "••••") are not compared: the REST API hides the passwords
jq -n --slurpfile a $tmp_dir/a.json --slurpfile b $tmp_dir/b.json --arg defaults "$defaults" '
  def masked: (. // "") | tostring | test("^(\\*+|\\[hidden\\])$") or contains("••");
  def str: if . == null then null else (if type == "string" then . else tojson end) end;
  # __internal.config.version is added by the worker (Kafka 4)
  def clean: del(.name) | with_entries(select(.key | startswith("__internal.") | not));
  ($a[0] | clean) as $A | ($b[0] | clean) as $B
  | if $defaults != "" then
      # only the keys set on the connector, compared with the default of the parameter
      [ $A | to_entries[] | .key as $k | (.value | str) as $va
        | if ($B | has($k) | not) then {key: $k, status: "no_default", a: $va}
          elif ($va | masked) then {key: $k, status: "masked", a: $va, b: ($B[$k] | str)}
          elif $B[$k] == null then {key: $k, status: "required", a: $va}
          elif $va == ($B[$k] | str) then {key: $k, status: "same", a: $va, b: ($B[$k] | str)}
          else {key: $k, status: "different", a: $va, b: ($B[$k] | str)} end ]
    else
      [ (($A | keys) + ($B | keys) | unique)[] as $k
        | ($A[$k] | str) as $va | ($B[$k] | str) as $vb
        | if ($A | has($k) | not) then {key: $k, status: "only_b", b: $vb}
          elif ($B | has($k) | not) then {key: $k, status: "only_a", a: $va}
          elif ($va | masked) or ($vb | masked) then {key: $k, status: "masked", a: $va, b: $vb}
          elif $va == $vb then {key: $k, status: "same", a: $va, b: $vb}
          else {key: $k, status: "different", a: $va, b: $vb} end ]
    end' > $tmp_dir/diff.json

if [[ -n "$json" ]]
then
    jq --arg a "$label_a" --arg b "$label_b" '{a: $a, b: $b, keys: .}' $tmp_dir/diff.json
    exit 0
fi

# side by side HTML report, with the documentation and default of each key from the configuration reference of the plugin
function write_diff_report () {
    local connector_class reference report
    if ! command -v python3 > /dev/null 2>&1
    then
        logwarn "⚠️ python3 is not on PATH: no HTML report"
        return 0
    fi
    connector_class=$(jq -r '."connector.class" // empty' $tmp_dir/a.json)
    # the reference of the running version (written by playground connector status / show-config), else the one recorded by CI
    reference=$(ls -t "$root_folder"/.connector_config/config-"$connector_class"-*.txt 2>/dev/null | head -1)
    if [[ -z "$reference" ]] && [[ -n "$connector_class" ]]
    then
        reference=$(cd "$root_folder" && git ls-files -- "*/config-$connector_class.txt" 2>/dev/null | head -1)
        [[ -n "$reference" ]] && reference="$root_folder/$reference"
    fi
    mkdir -p "$output_dir"
    output_dir=$(cd "$output_dir" && pwd)
    report="$output_dir/diff-$(printf '%s' "$connector-$label_b" | tr -c 'A-Za-z0-9._-' '_')-$(date '+%Y%m%d-%H%M%S').html"
    report_args=(--diff $tmp_dir/diff.json --a "$label_a" --b "$label_b" --connector-class "$connector_class" --html-out "$report")
    [[ -n "$defaults" ]] && report_args+=(--defaults)
    [[ -n "$reference" ]] && report_args+=(--reference "$reference")
    if ! python3 -I "$root_folder/tools/connector-diff/diff_report.py" "${report_args[@]}"
    then
        logerror "❌ could not write the HTML report"
        return 1
    fi
    open_html_report "$report" "$no_open"
}

if [[ -n "$defaults" ]]
then
    log "🔀 Parameters of connector $connector that are not at their default value"
    jq -r '
      def short: if . == null then "(null)" elif length > 120 then .[0:120] + "…" else . end;
      (.[] | select(.status == "required") | "  📌 \(.key) = \(.a | short)   (no default value)"),
      (.[] | select(.status == "different") | "  ✏️  \(.key) = \(.a | short)   (default: \(.b | if . == "" then "empty" else short end))"),
      (.[] | select(.status == "no_default") | "  🧩 \(.key) = \(.a | short)   (not a parameter of the plugin: worker override, transform, converter or predicate)"),
      (.[] | select(.status == "masked") | "  🔒 \(.key)   (masked by the REST API)")' $tmp_dir/diff.json
    same=$(jq '[.[] | select(.status == "same")] | length' $tmp_dir/diff.json)
    different=$(jq '[.[] | select(.status == "different")] | length' $tmp_dir/diff.json)
    log "📊 $different parameter(s) differ from their default, $same are set to their default value (they could be removed)"
    jq -r '.[] | select(.status == "same") | "  💤 \(.key) = \(.a)"' $tmp_dir/diff.json
    write_diff_report
    exit $?
fi

log "🔀 Diff of connector $connector (➖) with $label_b (➕)"
jq -r --arg a "$label_a" --arg b "$label_b" '
  def short: if . == null then "(null)" elif length > 120 then .[0:120] + "…" else . end;
  (.[] | select(.status == "different") | "  ✏️  \(.key)\n       ➖ \(.a | short)\n       ➕ \(.b | short)"),
  (.[] | select(.status == "only_a") | "  ➖ \(.key) = \(.a | short)   (only in \($a))"),
  (.[] | select(.status == "only_b") | "  ➕ \(.key) = \(.b | short)   (only in \($b))"),
  (.[] | select(.status == "masked") | "  🔒 \(.key)   (masked by the REST API, not compared)")' $tmp_dir/diff.json
same=$(jq '[.[] | select(.status == "same")] | length' $tmp_dir/diff.json)
differ=$(jq '[.[] | select(.status == "different" or .status == "only_a" or .status == "only_b")] | length' $tmp_dir/diff.json)
if [ "$differ" == "0" ]
then
    log "✅ no difference ($same identical keys)"
else
    log "📊 $differ key(s) differ, $same identical"
fi
write_diff_report
