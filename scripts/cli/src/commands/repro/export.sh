eval "files=(${args[--file]:-})"
all_uncommitted="${args[--all-uncommitted]}${args[--all]}"
output="${args[--output]}"
dry_run="${args[--dry-run]}"
force="${args[--force]}"
include_artifacts="${args[--include-artifacts]}"
no_clipboard="${args[--no-clipboard]}"
no_report="${args[--no-report]}"
report_only="${args[--report-only]}"

# with --report-only, only the report goes to stdout
if [[ -n "$report_only" ]]
then
    exec 3>&1 1>&2
fi

# the hand-off report of a model ($1 script, $2 its entry of the manifest, $3 name of the bundle), in Markdown
function repro_write_report () {
    local script="$1" model="$2" bundle="$3"
    local description case_number jira status expected actual author base_example base_script prefix
    description=$(jq -r '.description // ""' <<< "$model")
    case_number=$(jq -r '.case // ""' <<< "$model")
    jira=$(jq -r '.jira // ""' <<< "$model")
    status=$(jq -r '.status // ""' <<< "$model")
    expected=$(jq -r '.expected // ""' <<< "$model")
    actual=$(jq -r '.actual // ""' <<< "$model")
    author=$(jq -r '.author // ""' <<< "$model")
    base_example=$(jq -r '.base_example // ""' <<< "$model")

    echo "# 🐞 ${description:-$(basename "$script" .sh)}"
    echo ""
    echo "| | |"
    echo "| --- | --- |"
    [ -n "$case_number" ] && echo "| 🔮 case | [$case_number](https://confluent.zendesk.com/agent/tickets/$case_number) |"
    [ -n "$jira" ] && echo "| 🎫 jira | $jira |"
    echo "| 🩹 status | ${status:-not set} |"
    [ -n "$author" ] && echo "| 👤 author | $author |"
    [ -n "$base_example" ] && echo "| 🧬 based on | [\`$base_example\`](https://github.com/vdesabou/kafka-docker-playground/tree/master/$base_example) |"
    echo "| 🧪 last verdict | $(jq -r 'if .last_verdict == null then "none: the model does not end with `playground repro assert`, or it was not run" else (if .last_verdict.verdict == "reproduced" then "🐞 reproduced" else "✅ not reproduced" end) + " on \(.last_verdict.date[0:10]) (CP \(if .last_verdict.cp_version == "" then "default" else .last_verdict.cp_version end)" + (if .last_verdict.connector_version != "" then ", connector \(.last_verdict.connector_version)" else "" end) + "): \(.last_verdict.reason)" end' <<< "$model") |"
    echo ""
    echo "## 🎯 Expected"
    echo ""
    echo "${expected:-_not written in the header of the model (\`# 🎯 expected:\`)_}"
    echo ""
    echo "## 💥 Actual"
    echo ""
    echo "${actual:-_not written in the header of the model (\`# 💥 actual:\`)_}"
    echo ""
    # free text of the header: the lines under '# 💬 comments:' that are not fields
    comments=$(awk '/^# [^ ]+ comments:/ { on = 1; next } on && /^#####/ { exit } on' "$script" | grep -vE '^# [^ ]+ (expected|actual|jira|status):|^#[[:space:]]*$' | sed -E 's/^# ?//')
    if [ -n "$comments" ]
    then
        echo "## 💬 Comments"
        echo ""
        echo "$comments"
        echo ""
    fi
    echo "## ▶️ How to run it"
    echo ""
    echo '```bash'
    echo "playground repro import -f $bundle"
    jq -r '.run_command | sub("\\{repro_dir\\}"; "<printed by import>")' <<< "$model"
    echo '```'
    echo ""
    credentials=$(jq -r '.credentials | join(", ")' <<< "$model")
    [ -n "$credentials" ] && echo "🔑 Needs: $credentials (\`playground secrets set <NAME>\`, or the cloud credentials of the helper)." && echo ""
    external=$(jq -r '.external_files | join(", ")' <<< "$model")
    [ -n "$external" ] && echo "📎 Runs with files outside the repository: $external." && echo ""

    # what the model changes: its scenario (no header, no cheat sheet) compared with the script of the base example
    prefix=$(basename "$script" | sed -E 's/-repro-.*$//')
    base_script="$root_folder/$base_example/$prefix.sh"
    if [ -n "$base_example" ] && [ -f "$base_script" ]
    then
        # no header, no cheat sheet, no leading / trailing empty lines; the compose override renamed by bootstrap
        # (docker-compose.plaintext.repro-<description>.yml) gets back the name of the example's
        trim='{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++; for (i = s; i <= n; i++) print lines[i] }'
        awk 'banners < 2 { if (/^#####/) banners++; next } /^# 🧪 end the scenario with its verdict|^# 🧠 below is a list of cli commands/ { exit } { print }' "$script" \
            | sed -E 's/\.repro-[A-Za-z0-9-]+\.yml/.yml/g' | awk "$trim" > "$tmp_dir/report_model"
        grep -v '^#!/bin/bash' "$base_script" | awk "$trim" > "$tmp_dir/report_base"
        echo "## 🔀 What it changes compared with \`$base_example/$prefix.sh\`"
        echo ""
        if diff -q "$tmp_dir/report_base" "$tmp_dir/report_model" > /dev/null
        then
            echo "Nothing yet: the scenario is the one of the example."
        else
            echo '```diff'
            diff -u --label "$base_example/$prefix.sh" --label "$(basename "$script")" "$tmp_dir/report_base" "$tmp_dir/report_model" | head -300 || true
            echo '```'
        fi
        echo ""
        # and its docker compose override, when it changed
        model_override=$(grep -oE 'docker-compose\.[A-Za-z0-9.-]*repro-[A-Za-z0-9-]+\.yml' "$script" | head -1)
        base_override=$(echo "$model_override" | sed -E 's/\.repro-[A-Za-z0-9-]+\.yml/.yml/')
        if [ -n "$model_override" ] && [ -f "$(dirname "$script")/$model_override" ] && [ -f "$root_folder/$base_example/$base_override" ] \
            && ! diff -q "$root_folder/$base_example/$base_override" "$(dirname "$script")/$model_override" > /dev/null
        then
            echo "## 🐳 What it changes in \`$base_example/$base_override\`"
            echo ""
            echo '```diff'
            diff -u --label "$base_example/$base_override" --label "$model_override" "$root_folder/$base_example/$base_override" "$(dirname "$script")/$model_override" | head -200 || true
            echo '```'
            echo ""
        fi
    fi
    echo "---"
    echo "_Generated by \`playground repro export\` on $(date -u +%Y-%m-%d) from playground commit $(git -C "$root_folder" rev-parse --short HEAD 2>/dev/null)._"
}


if [ ! -z "$OUTPUT_FOLDER" ]
then
  output_folder="$OUTPUT_FOLDER"
else
  output_folder="reproduction-models"
fi

if [ "$output_folder" != "reproduction-models" ]
then
    logerror "❌ OUTPUT_FOLDER $output_folder is not set with reproduction-models, this is the only supported value !"
    exit 1
fi

if [ ! -d "$root_folder/$output_folder" ]
then
    logerror "❌ folder $root_folder/$output_folder does not exist"
    exit 1
fi
repro_root=$(cd -P "$root_folder/$output_folder" && pwd)

# 1. the models to export
declare -a scripts=()
declare -a extra_files=()
if [[ -n "$all_uncommitted" ]]
then
    if [ ! -e "$repro_root/.git" ]
    then
        logerror "❌ --all-uncommitted needs $repro_root to be a git repository"
        exit 1
    fi
    # untracked and modified files, untracked folders expanded, deleted files left out
    while IFS= read -r line
    do
        status="${line:0:2}"
        path="${line:3}"
        path="${path##* -> }"
        if [[ "$status" == *D* ]] || [ ! -e "$repro_root/$path" ] || [ -d "$repro_root/$path" ] || [[ "$path" != */* ]]
        then
            continue
        fi
        if git -C "$repro_root" check-ignore -q "$path" 2>/dev/null || repro_bundle_denied "${path#*/}"
        then
            continue
        fi
        case "$path" in
            */stop.sh) extra_files+=("$path") ;;
            */*/*) extra_files+=("$path") ;;
            *.sh) scripts+=("$repro_root/$path") ;;
            *) extra_files+=("$path") ;;
        esac
    done < <(git -C "$repro_root" status --porcelain --untracked-files=all 2>/dev/null)

    if [ ${#scripts[@]} -eq 0 ] && [ ${#extra_files[@]} -eq 0 ]
    then
        logerror "❌ No uncommitted reproduction model found in $repro_root"
        exit 1
    fi
elif [ ${#files[@]} -eq 0 ]
then
    test_file=$(playground state get run.test_file)
    if [ -z "$test_file" ] || [ ! -f "$test_file" ]
    then
        logerror "❌ No current reproduction model (run.test_file is <$test_file>), use --file to say which one to export"
        exit 1
    fi
    scripts=("$test_file")
else
    for file in "${files[@]}"
    do
        if [[ $file == *"@"* ]]
        then
            file=$(echo "$file" | cut -d "@" -f 2)
        fi
        scripts+=("$file")
    done
fi

# every model must be a script directly in a folder of reproduction-models
declare -a model_scripts=()
for script in "${scripts[@]}"
do
    script_dir=$(cd -P "$(dirname "$script")" 2>/dev/null && pwd)
    if [ "$(dirname "$script_dir")" != "$repro_root" ]
    then
        logerror "❌ $script is not a reproduction model of $repro_root, only those can be exported"
        exit 1
    fi
    model_scripts+=("$script_dir/$(basename "$script")")
done

if [ ${#model_scripts[@]} -eq 1 ]
then
    bundle_name=$(basename "${model_scripts[0]}" .sh)
elif [[ -n "$all_uncommitted" ]]
then
    bundle_name="all-uncommitted"
else
    bundle_name="${#model_scripts[@]}-models"
fi
bundle_date=$(date +%Y-%m-%d)

# 2. the files of the bundle
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

for script in "${model_scripts[@]}"
do
    repro_bundle_files "$script" "$repro_root"
done > "$tmp_dir/files"
for file in "${extra_files[@]}"
do
    echo "$file"
done >> "$tmp_dir/files"
sort -u "$tmp_dir/files" -o "$tmp_dir/files"

if [ ! -s "$tmp_dir/files" ]
then
    logerror "❌ No file to export"
    exit 1
fi

# 3. the manifest
history_file="$root_folder/playground-run-history"
: > "$tmp_dir/models.json"
: > "$tmp_dir/artifacts"
for script in "${model_scripts[@]}"
do
    dir_name=$(basename "$(dirname "$script")")
    script_name=$(basename "$script")

    run_line=""
    run_flags=""
    if [ -f "$history_file" ]
    then
        run_line=$(grep -E "^playground run -f [^ ]*/$dir_name/$script_name( |$)" "$history_file" | tail -1)
        run_flags=$(echo "${run_line#playground run -f }" | cut -s -d " " -f 2- | sed -e 's/[[:space:]]*$//')
    fi
    if [ -z "$run_line" ]
    then
        logwarn "🤷 $dir_name/$script_name: no 'playground run' found in playground-run-history, the bundle will not say which flags to use"
    fi

    # the importer runs with their own Confluent Cloud cluster
    stripped_flags=$(sed -E -e 's/--cluster-(schema-registry-)?creds[ =][^ ]+ ?//g' -e 's/[[:space:]]*$//' <<< "$run_flags")
    if [ "$stripped_flags" != "$run_flags" ]
    then
        log "🔐 $dir_name/$script_name: --cluster-creds / --cluster-schema-registry-creds removed from the run line"
        run_flags="$stripped_flags"
    fi

    # files outside the repository: --connector-zip / --connector-jar, and absolute paths in
    # the script or in the compose files it uses
    external_files=$(grep -oE -- "--connector-(zip|jar)=[^ ]+" <<< "$run_flags" | cut -d "=" -f 2- || true)
    {
        for external_file in $external_files
        do
            if [ -f "$external_file" ]
            then
                printf '%s\t%s\n' "$external_file" "$(cd -P "$(dirname "$external_file")" && pwd)/$(basename "$external_file")"
            fi
        done
        text_files=("$script")
        for file in $(grep -E "^$dir_name/[^/]*\.(yml|yaml)$" "$tmp_dir/files")
        do
            text_files+=("$repro_root/$file")
        done
        repro_external_paths "${text_files[@]}"
    } | sort -u > "$tmp_dir/external"
    while IFS=$'\t' read -r original source
    do
        if [[ -z "$include_artifacts" ]]
        then
            logwarn "📎 $dir_name/$script_name uses $original, which is outside the repository and not in the bundle: use --include-artifacts to add it"
            continue
        fi
        # same file already packed for this model (written differently)?
        artifact=$(awk -F'\t' -v s="$source" -v d="$dir_name/artifacts/" '$2 == s && index($1, d) == 1 { print $1; exit }' "$tmp_dir/artifacts")
        if [ -z "$artifact" ]
        then
            artifact="$dir_name/artifacts/$(basename "$source")"
            n=1
            while grep -q "^$artifact	" "$tmp_dir/artifacts"
            do
                n=$((n+1))
                artifact="$dir_name/artifacts/$n-$(basename "$source")"
            done
            if [ $(wc -c < "$source") -gt 52428800 ]
            then
                logwarn "🐘 $source is larger than 50 MB, the bundle will be big"
            fi
            echo "$artifact" >> "$tmp_dir/files"
        fi
        printf '%s\t%s\t%s\n' "$artifact" "$source" "$original" >> "$tmp_dir/artifacts"
    done < "$tmp_dir/external"

    description=$(repro_header_value "$script" "description")
    case_number=""
    if [[ "$description" =~ ^[0-9]{6} ]]
    then
        case_number="${BASH_REMATCH[0]}"
    fi
    author=$(repro_header_value "$script" "author")
    expected=$(repro_header_value "$script" "expected")
    actual=$(repro_header_value "$script" "actual")
    jira=$(repro_header_value "$script" "jira")
    status=$(repro_header_value "$script" "status")
    last_verdict=$(repro_last_verdict "$script")

    # the base example is where the symlinks created by bootstrap point to
    base_example=""
    for file in $(grep "^$dir_name/[^/]*$" "$tmp_dir/files")
    do
        if [ -L "$repro_root/$file" ]
        then
            target=$(repro_link_target "$output_folder/$file")
            if [ -n "$target" ] && [[ "$target" != "$output_folder"/* ]]
            then
                base_example=$(dirname "$target")
                break
            fi
        fi
    done

    credentials=$(repro_required_credentials "$script")

    jq -n \
        --arg script "$dir_name/$script_name" \
        --arg description "$description" \
        --arg case "$case_number" \
        --arg author "$author" \
        --arg base_example "$base_example" \
        --arg expected "$expected" \
        --arg actual "$actual" \
        --arg jira "$jira" \
        --arg status "$status" \
        --argjson last_verdict "${last_verdict:-null}" \
        --arg run_flags "$run_flags" \
        --arg credentials "$credentials" \
        --arg external_files "$external_files" \
        '{
            script: $script,
            description: $description,
            case: $case,
            author: $author,
            base_example: $base_example,
            expected: $expected,
            actual: $actual,
            jira: $jira,
            status: $status,
            last_verdict: ($last_verdict | if . == null then null else del(.script) end),
            run_flags: $run_flags,
            run_command: ("playground run -f {repro_dir}/" + ($script | split("/") | last) + (if $run_flags == "" then "" else " " + $run_flags end)),
            credentials: ($credentials | split("\n") | map(select(. != ""))),
            external_files: ($external_files | split("\n") | map(select(. != "")))
        }' >> "$tmp_dir/models.json"
done

# the hand-off report of each model, <model>.REPRO.md next to its script: what it shows, how to run it, what it changes
# compared with its base example. Listed in the manifest like the other files (an older playground imports it too)
: > "$tmp_dir/generated"
if [[ ! -n "$no_report" ]]
then
    while IFS= read -r model
    do
        script=$(jq -r '.script' <<< "$model")
        report="${script%.sh}.REPRO.md"
        mkdir -p "$tmp_dir/reports/$(dirname "$report")"
        repro_write_report "$repro_root/$script" "$model" "playground_repro_${bundle_name}_${bundle_date}.tgz" > "$tmp_dir/reports/$report"
        echo "$report" >> "$tmp_dir/files"
        printf '%s\t%s\t\n' "$report" "$tmp_dir/reports/$report" >> "$tmp_dir/generated"
    done < <(jq -c '.' "$tmp_dir/models.json")
fi
# where each file of the bundle is read from: the artifacts (outside the repository) and the generated reports
cat "$tmp_dir/artifacts" "$tmp_dir/generated" > "$tmp_dir/sources"

sort -u "$tmp_dir/files" -o "$tmp_dir/files"

: > "$tmp_dir/files.json"
while IFS= read -r file
do
    link_to=""
    if [ -L "$repro_root/$file" ]
    then
        target=$(repro_link_target "$output_folder/$file")
        # only links to the public examples can be restored on import
        if [ -n "$target" ] && [[ "$target" != "$output_folder"/* ]]
        then
            link_to="$target"
        fi
    fi
    jq -n \
        --arg path "$file" \
        --arg sha256 "$(repro_sha256 "$(repro_bundle_source "$repro_root" "$tmp_dir/sources" "$file")")" \
        --arg link_to "$link_to" \
        '{ path: $path, sha256: $sha256 } + (if $link_to == "" then {} else { link_to: $link_to } end)' >> "$tmp_dir/files.json"
done < "$tmp_dir/files"

playground_commit=$(git -C "$root_folder" rev-parse --short HEAD 2>/dev/null)
# paths of this checkout, that import rewrites to the importer's (e.g. --custom-smt jar path)
jq -n \
    --arg exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg exported_by "$(whoami)" \
    --arg playground_commit "$playground_commit" \
    --arg repro_roots "$(printf '%s\n%s' "$root_folder/$output_folder" "$repro_root")" \
    --arg root_folders "$(printf '%s\n%s' "$root_folder" "$(cd -P "$root_folder" && pwd)")" \
    --rawfile artifacts "$tmp_dir/artifacts" \
    --slurpfile models "$tmp_dir/models.json" \
    --slurpfile files "$tmp_dir/files.json" \
    '{
        format: 1,
        exported_at: $exported_at,
        exported_by: $exported_by,
        playground_commit: $playground_commit,
        source_repro_roots: ($repro_roots | split("\n") | unique),
        source_root_folders: ($root_folders | split("\n") | unique),
        artifacts: [ $artifacts | split("\n")[] | select(. != "") | split("\t") | { path: .[0], original: .[2] } ],
        models: $models,
        files: $files
    }' > "$tmp_dir/repro-manifest.json"

# 4. show what goes in
nb_files=$(wc -l < "$tmp_dir/files" | tr -d ' ')
log "👷‍♂️ ${#model_scripts[@]} reproduction model(s), $nb_files file(s):"
jq -r '.models[] | "   🔖 \(.script)\n      ▶️  \(.run_command)" + (if (.credentials | length) > 0 then "\n      🔑 needs: \(.credentials | join(", "))" else "" end)' "$tmp_dir/repro-manifest.json"
jq -r '.artifacts as $artifacts | .files[] | .path as $path | "   📄 \(.path)" + (if .link_to then "  (symlink to \(.link_to), stored as content)" else "" end) + ([ $artifacts[] | select(.path == $path) | .original ] | if length > 0 then "  (artifact, from \(join(", ")))" else "" end)' "$tmp_dir/repro-manifest.json"

# 5. secrets and customer data, before anything leaves the machine
log "🕵️ scanning the bundle for secrets and customer data"
repro_bundle_scan "$repro_root" "$tmp_dir/files" "$tmp_dir/repro-manifest.json" "$tmp_dir/findings" "$(jq -r '[.models[].base_example | select(. != "")] | unique | join(" ")' "$tmp_dir/repro-manifest.json")" "$tmp_dir/sources"
nb_blocks=$(grep -c "^block" "$tmp_dir/findings" || true)
nb_warnings=$(grep -c "^warn" "$tmp_dir/findings" || true)
repro_show_findings "$tmp_dir/findings"
if [ $nb_warnings -gt 0 ]
then
    logwarn "👀 $nb_warnings possible customer data finding(s): check them, a bundle must not contain customer data"
fi
if [ $nb_blocks -gt 0 ]
then
    if [[ -n "$force" ]]
    then
        logwarn "🔓 $nb_blocks secret finding(s), exporting anyway as --force is set"
    else
        logerror "❌ $nb_blocks secret finding(s): remove them (use \${VAR} instead of the value), or use --force if they are not real secrets"
        exit 1
    fi
elif [ $nb_warnings -eq 0 ]
then
    log "✅ no secret nor customer data found"
fi

if [[ -n "$report_only" ]]
then
    if [ ! -s "$tmp_dir/generated" ]
    then
        logerror "❌ --report-only and --no-report can't be used together"
        exit 1
    fi
    first=1
    while IFS=$'\t' read -r report source rest
    do
        [ -z "$first" ] && echo "" >&3
        cat "$source" >&3
        first=""
    done < "$tmp_dir/generated"
    exit 0
fi

if [[ -n "$dry_run" ]]
then
    log "🔍 dry run: no bundle written"
    exit 0
fi

# 6. the bundle: symlinks are stored as their content
staging="$tmp_dir/staging"
mkdir -p "$staging"
while IFS= read -r file
do
    mkdir -p "$staging/$(dirname "$file")"
    cp -pL "$(repro_bundle_source "$repro_root" "$tmp_dir/sources" "$file")" "$staging/$file"
done < "$tmp_dir/files"
cp "$tmp_dir/repro-manifest.json" "$staging/"

if [[ -n "$output" ]]
then
    output_dir="${output/#\~/$HOME}"
else
    output_dir="$PWD"
    # never inside the submodule: the bundle would end up in the next export
    if [[ "$(cd -P "$output_dir" && pwd)/" == "$repro_root/"* ]]
    then
        output_dir="$root_folder"
    fi
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
final_archive="$output_dir/playground_repro_${bundle_name}_${bundle_date}.tgz"

if ! (cd "$staging" && tar czf "$final_archive" repro-manifest.json $(cut -d "/" -f 1 "$tmp_dir/files" | sort -u))
then
    logerror "❌ export failed as archive $final_archive could not be created !"
    exit 1
fi

log "📤 Exported bundle is available: $final_archive ($(du -h "$final_archive" | cut -f 1 | tr -d ' '))"
log "📥 To import it: playground repro import -f <path>/$(basename "$final_archive")"
while IFS=$'\t' read -r report source rest
do
    log "📖 hand-off report in the bundle: $report (read it: tar xzOf $final_archive $report)"
done < "$tmp_dir/generated"

# the bundle itself (not its path) goes to the clipboard: Cmd+V in Slack, Zendesk or a mail attaches it.
# Always, unless --no-clipboard: the 'clipboard' config is about the run line and connector configs
if [[ "$OSTYPE" == "darwin"* ]] && [[ ! -n "$no_clipboard" ]]
then
    if osascript -e "set the clipboard to (POSIX file \"$final_archive\")" > /dev/null 2>&1
    then
        log "📋 bundle copied to the clipboard as a file: paste it (Cmd+V) in a Slack conversation to attach it (--no-clipboard to skip)"
    else
        logwarn "📋 could not copy the bundle to the clipboard, attach $final_archive by hand"
    fi
fi
