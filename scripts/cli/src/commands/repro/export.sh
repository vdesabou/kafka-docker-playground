eval "files=(${args[--file]:-})"
all_uncommitted="${args[--all-uncommitted]}${args[--all]}"
output="${args[--output]}"
dry_run="${args[--dry-run]}"
force="${args[--force]}"

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

    # files given by absolute path on this machine are not in the bundle
    external_files=$(grep -oE -- "--connector-(zip|jar)=[^ ]+" <<< "$run_flags" | cut -d "=" -f 2-)
    for external_file in $external_files
    do
        logwarn "📎 $dir_name/$script_name runs with $external_file, which is not included in the bundle: send it too"
    done

    description=$(repro_header_value "$script" "description")
    case_number=""
    if [[ "$description" =~ ^[0-9]{6} ]]
    then
        case_number="${BASH_REMATCH[0]}"
    fi
    author=$(repro_header_value "$script" "author")

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
        --arg run_flags "$run_flags" \
        --arg credentials "$credentials" \
        --arg external_files "$external_files" \
        '{
            script: $script,
            description: $description,
            case: $case,
            author: $author,
            base_example: $base_example,
            run_flags: $run_flags,
            run_command: ("playground run -f {repro_dir}/" + ($script | split("/") | last) + (if $run_flags == "" then "" else " " + $run_flags end)),
            credentials: ($credentials | split("\n") | map(select(. != ""))),
            external_files: ($external_files | split("\n") | map(select(. != "")))
        }' >> "$tmp_dir/models.json"
done

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
        --arg sha256 "$(repro_sha256 "$repro_root/$file")" \
        --arg link_to "$link_to" \
        '{ path: $path, sha256: $sha256 } + (if $link_to == "" then {} else { link_to: $link_to } end)' >> "$tmp_dir/files.json"
done < "$tmp_dir/files"

playground_commit=$(git -C "$root_folder" rev-parse --short HEAD 2>/dev/null)
jq -n \
    --arg exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg exported_by "$(whoami)" \
    --arg playground_commit "$playground_commit" \
    --slurpfile models "$tmp_dir/models.json" \
    --slurpfile files "$tmp_dir/files.json" \
    '{
        format: 1,
        exported_at: $exported_at,
        exported_by: $exported_by,
        playground_commit: $playground_commit,
        models: $models,
        files: $files
    }' > "$tmp_dir/repro-manifest.json"

# 4. show what goes in
nb_files=$(wc -l < "$tmp_dir/files" | tr -d ' ')
log "👷‍♂️ ${#model_scripts[@]} reproduction model(s), $nb_files file(s):"
jq -r '.models[] | "   🔖 \(.script)\n      ▶️  \(.run_command)" + (if (.credentials | length) > 0 then "\n      🔑 needs: \(.credentials | join(", "))" else "" end)' "$tmp_dir/repro-manifest.json"
jq -r '.files[] | "   📄 \(.path)" + (if .link_to then "  (symlink to \(.link_to), stored as content)" else "" end)' "$tmp_dir/repro-manifest.json"

# 5. secrets and customer data, before anything leaves the machine
log "🕵️ scanning the bundle for secrets and customer data"
repro_bundle_scan "$repro_root" "$tmp_dir/files" "$tmp_dir/repro-manifest.json" "$tmp_dir/findings" "$(jq -r '[.models[].base_example | select(. != "")] | unique | join(" ")' "$tmp_dir/repro-manifest.json")"
nb_blocks=$(grep -c "^block" "$tmp_dir/findings" || true)
nb_warnings=$(grep -c "^warn" "$tmp_dir/findings" || true)
for severity in block warn
do
    grep "^$severity" "$tmp_dir/findings" | head -20 | while IFS=$'\t' read -r level location message
    do
        if [ "$level" == "block" ]
        then
            logerror "   🔐 $location $message"
        else
            logwarn "   👀 $location $message"
        fi
    done
done
if [ $((nb_blocks + nb_warnings)) -gt 40 ]
then
    logwarn "   … $((nb_blocks + nb_warnings)) findings in total, only the first 20 of each kind are shown"
fi
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
    cp -pL "$repro_root/$file" "$staging/$file"
done < "$tmp_dir/files"
cp "$tmp_dir/repro-manifest.json" "$staging/"

if [ ${#model_scripts[@]} -eq 1 ]
then
    bundle_name=$(basename "${model_scripts[0]}" .sh)
elif [[ -n "$all_uncommitted" ]]
then
    bundle_name="all-uncommitted"
else
    bundle_name="${#model_scripts[@]}-models"
fi

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
final_archive="$output_dir/playground_repro_${bundle_name}_$(date +%Y-%m-%d).tgz"

if ! (cd "$staging" && tar czf "$final_archive" repro-manifest.json $(cut -d "/" -f 1 "$tmp_dir/files" | sort -u))
then
    logerror "❌ export failed as archive $final_archive could not be created !"
    exit 1
fi

log "📤 Exported bundle is available: $final_archive ($(du -h "$final_archive" | cut -f 1 | tr -d ' '))"
log "📥 To import it: playground repro import -f <path>/$(basename "$final_archive")"
