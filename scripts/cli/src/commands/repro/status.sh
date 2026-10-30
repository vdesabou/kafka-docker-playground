file="${args[--file]}"
new_status="${args[--set]}"
new_expected="${args[--expected]}"
new_actual="${args[--actual]}"
new_jira="${args[--jira]}"
json="${args[--json]}"

if [ -z "$file" ]
then
    file=$(playground state get run.test_file)
    if [ -z "$file" ] || [ ! -f "$file" ]
    then
        logerror "❌ No current reproduction model (run.test_file is <$file>), use --file to say which one"
        exit 1
    fi
fi
if [[ $file == *"@"* ]]
then
    file=$(echo "$file" | cut -d "@" -f 2)
fi

if ! head -30 "$file" | grep -qE "^# [^ ]+ description: "
then
    logerror "❌ $file is not a reproduction model: its header has no '# 💡 description:' line (create models with 'playground repro bootstrap')"
    exit 1
fi

# 1. updates, in the order of the header
declare -a updated=()
for key in $(repro_header_fields)
do
    case "$key" in
        expected) value="$new_expected" ;;
        actual) value="$new_actual" ;;
        jira) value=$(repro_jira_url "$new_jira") ;;
        status) value="$new_status" ;;
    esac
    if [ -n "$value" ]
    then
        repro_header_set_value "$file" "$key" "${value//$'\n'/ }" || exit 1
        updated+=("$key")
    fi
done

# 2. the fields
description=$(repro_header_value "$file" "description")
case_number=""
if [[ "$description" =~ ^[0-9]{6} ]]
then
    case_number="${BASH_REMATCH[0]}"
fi
author=$(repro_header_value "$file" "author")
created=$(repro_header_value "$file" "date")
# the base example is where the support files linked by bootstrap point to
base_example=""
for link in README.md stop.sh
do
    target=$(readlink "$(dirname "$file")/$link" 2>/dev/null)
    if [[ "$target" == ../../* ]]
    then
        base_example=$(dirname "${target#../../}")
        break
    fi
done
expected=$(repro_header_value "$file" "expected")
actual=$(repro_header_value "$file" "actual")
jira=$(repro_header_value "$file" "jira")
status=$(repro_header_value "$file" "status")

if [[ -n "$json" ]]
then
    jq -n \
        --arg script "$file" \
        --arg description "$description" \
        --arg case "$case_number" \
        --arg author "$author" \
        --arg created "$created" \
        --arg base_example "$base_example" \
        --arg expected "$expected" \
        --arg actual "$actual" \
        --arg jira "$jira" \
        --arg status "$status" \
        --arg updated "${updated[*]}" \
        '{script: $script, description: $description, case: $case, author: $author, created: $created, base_example: $base_example,
          expected: $expected, actual: $actual, jira: $jira, status: $status,
          updated: ($updated | split(" ") | map(select(. != "")))}'
    exit 0
fi

if [ ${#updated[@]} -gt 0 ]
then
    log "✏️  updated in the header: ${updated[*]}"
fi
log "🔖 $file"
log "   💡 description: $description"
[ -n "$case_number" ] && log "   🔮 ticket: https://confluent.zendesk.com/agent/tickets/$case_number"
[ -n "$author" ] && log "   👤 author: $author${created:+ ($created)}"
[ -n "$base_example" ] && log "   🧬 based on: $base_example"
missing=""
for key in $(repro_header_fields)
do
    value=$(repro_header_value "$file" "$key")
    if [ -n "$value" ]
    then
        log "   $(repro_header_emoji "$key") $key: $value"
    else
        logwarn "   $(repro_header_emoji "$key") $key: (empty)"
        missing="$missing --$( [ "$key" == "status" ] && echo "set" || echo "$key" ) \"…\""
    fi
done
if [ -n "$missing" ]
then
    log "💡 fill in the empty fields: playground repro status -f $file$missing"
fi
