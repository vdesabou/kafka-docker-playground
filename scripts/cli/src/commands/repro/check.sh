eval "files=(${args[--file]:-})"
staged="${args[--staged]}"
all="${args[--all]}"
skip_secrets_store="${args[--skip-secrets-store]}"
json="${args[--json]}"

repro_root="$root_folder/reproduction-models"
if [ ! -d "$repro_root" ]
then
    logerror "❌ folder $repro_root does not exist"
    exit 1
fi
repro_root=$(cd -P "$repro_root" && pwd)

if [ ${#files[@]} -eq 0 ] && [ ! -e "$repro_root/.git" ]
then
    logerror "❌ $repro_root is not a git repository, use --file to say which model to check"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
: > "$tmp_dir/candidates"
: > "$tmp_dir/artifacts"

# 1. the files to check, relative to reproduction-models
if [[ -n "$staged" ]]
then
    git -C "$repro_root" diff --cached --name-only --diff-filter=ACMR > "$tmp_dir/candidates"
    what="staged file(s)"
elif [[ -n "$all" ]]
then
    git -C "$repro_root" ls-files --cached --others --exclude-standard > "$tmp_dir/candidates"
    what="file(s)"
elif [ ${#files[@]} -gt 0 ]
then
    for file in "${files[@]}"
    do
        if [[ $file == *"@"* ]]
        then
            file=$(echo "$file" | cut -d "@" -f 2)
        fi
        script_dir=$(cd -P "$(dirname "$file")" 2>/dev/null && pwd)
        if [ "$(dirname "$script_dir")" != "$repro_root" ]
        then
            # stderr: the output of the loop goes to the candidates file
            logerror "❌ $file is not a reproduction model of $repro_root (a script directly in one of its folders)" >&2
            exit 1
        fi
        repro_bundle_files "$script_dir/$(basename "$file")" "$repro_root"
    done > "$tmp_dir/candidates"
    what="file(s)"
else
    # new and modified files, untracked folders expanded
    git -C "$repro_root" status --porcelain --untracked-files=all 2>/dev/null | while IFS= read -r line
    do
        status="${line:0:2}"
        path="${line:3}"
        if [[ "$status" != *D* ]]
        then
            echo "${path##* -> }"
        fi
    done > "$tmp_dir/candidates"
    what="uncommitted file(s)"
fi

# only the files of the model folders: not the dot folders (.github, .claude…), nor the
# symlinks to the public examples. Credential files, dumps, logs and archives are findings
# on their own: export leaves them out, but a commit would not
: > "$tmp_dir/files"
: > "$tmp_dir/file-findings"
while IFS= read -r path
do
    case "$path" in
        .*|*/.git/*|"") continue ;;
        */*) ;;
        *) continue ;;
    esac
    if [[ -n "$staged" ]]
    then
        mode=$(git -C "$repro_root" ls-files -s -- "$path" | awk '{ print $1; exit }')
        if [ "$mode" == "120000" ]
        then
            continue
        fi
    elif [ -L "$repro_root/$path" ] || [ ! -f "$repro_root/$path" ]
    then
        continue
    fi
    name="${path##*/}"
    case "$name" in
        keyfile.json|*.pem|*.key|*.p12|*.jks|secrets.properties|playground.ini|playground-run-history|.env)
            printf 'block\t%s\t%s\n' "$path" "is a credential file" >> "$tmp_dir/file-findings"
            continue
        ;;
        *.hprof|*.hprof.gz|*.jfr|*.log|*.tgz|*.tar.gz|*.zip)
            printf 'warn\t%s\t%s\n' "$path" "is a dump, log or archive: it may hold customer data" >> "$tmp_dir/file-findings"
            continue
        ;;
        repro-manifest.json|.DS_Store)
            continue
        ;;
    esac
    echo "$path" >> "$tmp_dir/files"
    if [[ -n "$staged" ]]
    then
        # what is committed is the staged content, not the working tree
        mkdir -p "$tmp_dir/index/$(dirname "$path")"
        git -C "$repro_root" show ":$path" > "$tmp_dir/index/$path" 2>/dev/null
        printf '%s\t%s\t%s\n' "$path" "$tmp_dir/index/$path" "$path" >> "$tmp_dir/artifacts"
    fi
done < <(sort -u "$tmp_dir/candidates")

nb_files=$(wc -l < "$tmp_dir/files" | tr -d ' ')
nb_file_findings=$(wc -l < "$tmp_dir/file-findings" | tr -d ' ')
if [ "$nb_files" -eq 0 ] && [ "$nb_file_findings" -eq 0 ]
then
    if [[ -n "$json" ]]
    then
        jq -n '{ files: 0, blocks: [], warnings: [] }'
    else
        log "🤷 no $what of a reproduction model to check"
    fi
    exit 0
fi

# 2. the scan
if [[ ! -n "$json" ]]
then
    log "🕵️ scanning $nb_files $what of reproduction models for secrets and customer data"
fi
: > "$tmp_dir/findings"
if [ "$nb_files" -gt 0 ]
then
    repro_bundle_scan "$repro_root" "$tmp_dir/files" "" "$tmp_dir/findings" "$(repro_model_base_examples "$repro_root" "$tmp_dir/files")" "$tmp_dir/artifacts" "$skip_secrets_store"
fi
cat "$tmp_dir/file-findings" >> "$tmp_dir/findings"
sort -u "$tmp_dir/findings" | sort -t $'\t' -k1,1 -k2,2V -o "$tmp_dir/findings"

nb_blocks=$(grep -c "^block" "$tmp_dir/findings" || true)
nb_warnings=$(grep -c "^warn" "$tmp_dir/findings" || true)

# 3. the result
if [[ -n "$json" ]]
then
    jq -R -s --argjson files "$nb_files" '
        split("\n") | map(select(. != "") | split("\t") | { level: .[0], location: .[1], message: .[2] }) as $findings
        | {
            files: $files,
            blocks: [ $findings[] | select(.level == "block") | { location, message } ],
            warnings: [ $findings[] | select(.level == "warn") | { location, message } ]
          }' "$tmp_dir/findings"
else
    repro_show_findings "$tmp_dir/findings"
    if [ $nb_warnings -gt 0 ]
    then
        logwarn "👀 $nb_warnings possible customer data finding(s): check them, a reproduction model must not contain customer data"
    fi
    if [ $nb_blocks -gt 0 ]
    then
        logerror "❌ $nb_blocks secret finding(s): remove them (use \${VAR} instead of the value)"
    elif [ $nb_warnings -eq 0 ]
    then
        log "✅ no secret nor customer data found"
    fi
fi

if [ $nb_blocks -gt 0 ]
then
    exit 1
fi
