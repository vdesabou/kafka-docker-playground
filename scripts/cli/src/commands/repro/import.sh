file="${args[--file]}"
on_conflict="${args[--on-conflict]}"
dry_run="${args[--dry-run]}"

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

if [[ $file == *"@"* ]]
then
  file=$(echo "$file" | cut -d "@" -f 2)
fi
file=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")

mkdir -p "$root_folder/$output_folder"
repro_root=$(cd -P "$root_folder/$output_folder" && pwd)

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# 1. extract into an empty folder, the bundle is untrusted
if ! tar tzf "$file" > "$tmp_dir/entries" 2>/dev/null
then
    logerror "❌ $file is not a tgz file"
    exit 1
fi
if grep -qE '^/|(^|/)\.\.(/|$)' "$tmp_dir/entries"
then
    logerror "❌ $file contains absolute paths or '..', refusing to import it:"
    grep -E '^/|(^|/)\.\.(/|$)' "$tmp_dir/entries" | head -10
    exit 1
fi

extract="$tmp_dir/extract"
mkdir -p "$extract"
if ! tar xzf "$file" -C "$extract"
then
    logerror "❌ could not extract $file"
    exit 1
fi

special_files=$(cd "$extract" && find . ! -type f ! -type d ! -type l)
if [ -n "$special_files" ]
then
    logerror "❌ $file contains special files, refusing to import it:"
    echo "$special_files" | head -10
    exit 1
fi

manifest="$extract/repro-manifest.json"
(cd "$extract" && find . \( -type f -o -type l \) ! -path ./repro-manifest.json | sed -e 's|^\./||' | sort) > "$tmp_dir/files"

# 2. validate
if [ -f "$manifest" ]
then
    if ! jq -e . "$manifest" > /dev/null 2>&1
    then
        logerror "❌ repro-manifest.json of $file is not valid json"
        exit 1
    fi
    format=$(jq -r '.format // 0' "$manifest")
    if [ "$format" != "1" ]
    then
        logerror "❌ bundle format $format is not supported by this version of the playground, update it with 'git pull'"
        exit 1
    fi
    # a bundle has no symlink, they are stored as content
    if [ -n "$(cd "$extract" && find . -type l)" ]
    then
        logerror "❌ $file contains symlinks, refusing to import it"
        exit 1
    fi
    jq -r '.files[].path' "$manifest" | sort > "$tmp_dir/manifest_files"
    if ! diff -q "$tmp_dir/files" "$tmp_dir/manifest_files" > /dev/null
    then
        logerror "❌ the files of $file do not match its manifest, refusing to import it:"
        diff "$tmp_dir/files" "$tmp_dir/manifest_files" | grep '^[<>]' | head -10
        exit 1
    fi
    while IFS=$'\t' read -r path sha256
    do
        if [ "$(repro_sha256 "$extract/$path")" != "$sha256" ]
        then
            logerror "❌ sha256 of $path does not match the manifest, refusing to import it"
            exit 1
        fi
    done < <(jq -r '.files[] | "\(.path)\t\(.sha256)"' "$manifest")
else
    logwarn "🗃️ legacy bundle without repro-manifest.json: no metadata (run flags, credentials), files are not verified"
    # former export kept the symlinks: only relative ones to a public example are accepted
    while IFS= read -r path
    do
        if [ -L "$extract/$path" ]
        then
            target=$(readlink "$extract/$path")
            normalized=""
            if [[ "$target" != /* ]]
            then
                normalized=$(repro_normalize_path "$output_folder/$(dirname "$path")/$target")
            fi
            if [ -z "$normalized" ] || [[ "$normalized" == "$output_folder"/* ]] || [ ! -e "$root_folder/$normalized" ]
            then
                logerror "❌ $path is a symlink to $target, which is not a file of a public example, refusing to import it"
                exit 1
            fi
        fi
    done < "$tmp_dir/files"
    # same layout as a manifest, without models nor checksums
    jq -R -s '{ format: 0, models: [ split("\n")[] | select(test("^[^/]+/[^/]+\\.sh$") and (endswith("/stop.sh") | not)) | { script: ., run_flags: "", credentials: [], external_files: [] } ], files: [ split("\n")[] | select(. != "") | { path: . } ] }' "$tmp_dir/files" > "$tmp_dir/legacy-manifest.json"
    manifest="$tmp_dir/legacy-manifest.json"
fi

# files at the top of the bundle are not in a model folder
top_files=$(grep -v "/" "$tmp_dir/files" || true)
if [ -n "$top_files" ]
then
    logwarn "⏭️ skipping files that are not in a reproduction model folder: $(echo $top_files)"
    grep "/" "$tmp_dir/files" > "$tmp_dir/files.tmp" || true
    mv "$tmp_dir/files.tmp" "$tmp_dir/files"
fi
if [ ! -s "$tmp_dir/files" ]
then
    logerror "❌ $file contains no reproduction model file"
    exit 1
fi

# 3. what is in it
exported_at=$(jq -r '.exported_at // empty' "$manifest")
if [ -n "$exported_at" ]
then
    log "📦 bundle exported on $exported_at by $(jq -r '.exported_by' "$manifest") from playground commit $(jq -r '.playground_commit' "$manifest")"
    playground_commit=$(jq -r '.playground_commit // empty' "$manifest")
    if [ -n "$playground_commit" ] && ! git -C "$root_folder" cat-file -e "$playground_commit^{commit}" 2>/dev/null
    then
        logwarn "🆕 commit $playground_commit is not in your checkout: the models may use features your playground does not have yet, consider 'git pull'"
    fi
fi
while IFS= read -r model
do
    log "🔖 $(jq -r '.script' <<< "$model")"
    description=$(jq -r '.description // empty' <<< "$model")
    [ -n "$description" ] && log "   💡 $description"
    case_number=$(jq -r '.case // empty' <<< "$model")
    [ -n "$case_number" ] && log "   🔮 https://confluent.zendesk.com/agent/tickets/$case_number"
    author=$(jq -r '.author // empty' <<< "$model")
    [ -n "$author" ] && log "   👤 $author"
    base_example=$(jq -r '.base_example // empty' <<< "$model")
    if [ -n "$base_example" ]
    then
        if [ -d "$root_folder/$base_example" ]
        then
            log "   🧬 based on $base_example"
        else
            logwarn "   🧬 based on $base_example, which does not exist in your checkout: the copies stored in the bundle are used"
        fi
    fi
done < <(jq -c '.models[]' "$manifest")

# 4. plan: new, identical or conflicting
date_suffix=$(date +%Y%m%d)
nb_new=0
nb_identical=0
declare -a conflicts=()
: > "$tmp_dir/plan"
while IFS= read -r path
do
    dest="$repro_root/$path"
    link_to=$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .link_to // empty' "$manifest")
    if [ -e "$dest" ]
    then
        # your copy links to the same public file (its content may have changed since, e.g. config-*.json)
        if [ -n "$link_to" ] && [ -L "$dest" ] && [ "$(repro_link_target "$output_folder/$path")" == "$link_to" ]
        then
            status="identical"
            nb_identical=$((nb_identical+1))
        elif cmp -s "$extract/$path" "$dest"
        then
            status="identical"
            nb_identical=$((nb_identical+1))
        else
            status="conflict"
            conflicts+=("$path")
        fi
    else
        status="new"
        nb_new=$((nb_new+1))
    fi
    printf '%s\t%s\n' "$status" "$path" >> "$tmp_dir/plan"
done < "$tmp_dir/files"

log "📋 $nb_new new, $nb_identical identical, ${#conflicts[@]} conflicting file(s)"
if [[ -n "$dry_run" ]] || [ ${#conflicts[@]} -gt 0 ]
then
    while IFS=$'\t' read -r status path
    do
        case "$status" in
            new) echo "   ✨ new        $path" ;;
            identical) echo "   🟰 identical  $path" ;;
            conflict) echo "   ⚔️  conflict   $path" ;;
        esac
    done < "$tmp_dir/plan"
fi

if [[ -n "$dry_run" ]]
then
    log "🔍 dry run: nothing imported"
    exit 0
fi

if [ ${#conflicts[@]} -gt 0 ] && [ "$on_conflict" == "abort" ]
then
    logerror "❌ ${#conflicts[@]} file(s) differ from your copy, nothing imported. Use --on-conflict rename (keeps yours) or --on-conflict overwrite"
    exit 1
fi

# 5. import
declare -a renames=()
while IFS=$'\t' read -r status path
do
    dest="$repro_root/$path"
    if [ "$status" == "identical" ]
    then
        continue
    fi
    if [ "$status" == "conflict" ]
    then
        if [ "$on_conflict" == "rename" ]
        then
            name=$(basename "$path")
            if [[ "$name" == *.* ]]
            then
                new_name="${name%.*}-imported-$date_suffix.${name##*.}"
            else
                new_name="$name-imported-$date_suffix"
            fi
            dest="$(dirname "$dest")/$new_name"
            renames+=("$name	$new_name")
            log "✏️  $path imported as $(dirname "$path")/$new_name"
        fi
        rm -f "$dest"
    fi
    mkdir -p "$(dirname "$dest")"

    if [ -L "$extract/$path" ]
    then
        # legacy bundle: the symlink was validated above
        rm -f "$dest"
        ln -s "$(readlink "$extract/$path")" "$dest"
        continue
    fi

    # restore the symlinks of bootstrap when the public file is identical
    link_to=$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .link_to // empty' "$manifest")
    if [ -n "$link_to" ] && [ -f "$root_folder/$link_to" ] && cmp -s "$extract/$path" "$root_folder/$link_to"
    then
        up=$(echo "$output_folder/$(dirname "$path")" | sed -e 's|[^/][^/]*|..|g')
        ln -s "$up/$link_to" "$dest"
    else
        if [ -n "$link_to" ]
        then
            logwarn "📄 $path differs from $link_to in your checkout, keeping the copy from the bundle"
        fi
        cp -p "$extract/$path" "$dest"
    fi
done < "$tmp_dir/plan"

# the final path of each model, with references to renamed files updated
declare -a model_paths=()
while IFS= read -r model
do
    script=$(jq -r '.script' <<< "$model")
    name=$(basename "$script")
    for rename in "${renames[@]}"
    do
        if [ "${rename%%	*}" == "$name" ]
        then
            name="${rename##*	}"
        fi
    done
    model_path="$repro_root/$(dirname "$script")/$name"
    model_paths+=("$model_path")
    for rename in "${renames[@]}"
    do
        sed -e "s|${rename%%	*}|${rename##*	}|g" "$model_path" > "$tmp_dir/script"
        cat "$tmp_dir/script" > "$model_path"
    done
done < <(jq -c '.models[]' "$manifest")

log "📥 $file imported in $repro_root"

if [ ${#model_paths[@]} -eq 0 ]
then
    exit 0
fi

# 6. register the first model as the current one, like bootstrap does
test_file="${model_paths[0]}"
playground state set run.test_file "$test_file"
playground state set run.connector_type "$(get_connector_type | tr -d '\n')"

# 7. how to run them
i=0
while IFS= read -r model
do
    model_path="${model_paths[$i]}"
    i=$((i+1))
    run_flags=$(jq -r '.run_flags // empty' <<< "$model")
    log "▶️  playground run -f $model_path${run_flags:+ $run_flags}"
    while IFS= read -r external_file
    do
        if [ -n "$external_file" ] && [ ! -f "$external_file" ]
        then
            logwarn "   📎 it runs with $external_file, which is not on this machine: ask for it and fix the path"
        fi
    done < <(jq -r '.external_files[]?' <<< "$model")
    while IFS= read -r credential
    do
        case "$credential" in
            "")
                ;;
            handle_*_credentials|bootstrap_ccloud_environment)
                log "   🔑 calls $credential, make sure the matching credentials are set up"
                ;;
            *)
                if [ -z "$(secret_get "$credential" 2>/dev/null)" ]
                then
                    logwarn "   🔑 $credential is not set: playground secrets set $credential"
                fi
                ;;
        esac
    done < <(jq -r '.credentials[]?' <<< "$model")
done < <(jq -c '.models[]' "$manifest")
