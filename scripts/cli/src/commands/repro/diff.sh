file="${args[--file]}"
compose_only="${args[--compose]}"
summary_only="${args[--summary]}"
json="${args[--json]}"

if [ -z "$file" ]
then
    file=$(playground state get run.test_file)
fi
if [[ $file == *"@"* ]]
then
    file=$(echo "$file" | cut -d "@" -f 2)
fi
if [ -z "$file" ] || [ ! -f "$file" ]
then
    logerror "❌ no reproduction model (run.test_file is <$file>), use --file"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if ! repro_diff_files "$file" "$tmp_dir"
then
    logerror "❌ the base example of $(basename "$file") was not found: its folder has no README.md / stop.sh symlink to an example, or ${REPRO_DIFF_BASE_SCRIPT:-its script} does not exist anymore"
    exit 1
fi

changes=$(repro_config_changes "$tmp_dir/base_scenario" "$tmp_dir/model_scenario")
scenario_changed=0
if ! diff -q "$tmp_dir/base_scenario" "$tmp_dir/model_scenario" > /dev/null
then
    scenario_changed=1
fi
override_changed=0
if [ -f "$tmp_dir/model_override" ] && ! diff -q "$tmp_dir/base_override" "$tmp_dir/model_override" > /dev/null
then
    override_changed=1
fi

if [[ -n "$json" ]]
then
    jq -n \
        --arg model "$file" \
        --arg base_script "$REPRO_DIFF_BASE_SCRIPT" \
        --arg model_override "$REPRO_DIFF_MODEL_OVERRIDE" \
        --arg base_override "$REPRO_DIFF_BASE_OVERRIDE" \
        --argjson connectors "$changes" \
        --arg scenario_diff "$(diff -u --label "$REPRO_DIFF_BASE_SCRIPT" --label "$(basename "$file")" "$tmp_dir/base_scenario" "$tmp_dir/model_scenario" || true)" \
        --arg override_diff "$( [ $override_changed -eq 1 ] && diff -u --label "$REPRO_DIFF_BASE_EXAMPLE/$REPRO_DIFF_BASE_OVERRIDE" --label "$REPRO_DIFF_MODEL_OVERRIDE" "$tmp_dir/base_override" "$tmp_dir/model_override" || true)" \
        '{model: $model, base_script: $base_script, base_override: $base_override, model_override: $model_override,
          connectors: $connectors, scenario_diff: $scenario_diff, override_diff: $override_diff}'
    exit 0
fi

# colors in a terminal only
if [ -t 1 ]
then
    colorize=(sed -e $'s/^-.*/\e[31m&\e[0m/' -e $'s/^+.*/\e[32m&\e[0m/' -e $'s/^@@.*/\e[36m&\e[0m/')
else
    colorize=(cat)
fi

log "🧬 $(basename "$file") compared with $REPRO_DIFF_BASE_SCRIPT"
if [ $scenario_changed -eq 0 ]
then
    log "🟰 scenario: the one of the example"
else
    repro_config_changes_lines "$changes" | while IFS= read -r line
    do
        log "$line"
    done
fi
if [ -f "$tmp_dir/model_override" ]
then
    if [ $override_changed -eq 0 ]
    then
        log "🟰 docker compose override: the one of the example ($REPRO_DIFF_BASE_OVERRIDE)"
    else
        log "🐳 docker compose override: $REPRO_DIFF_MODEL_OVERRIDE differs from $REPRO_DIFF_BASE_OVERRIDE"
    fi
fi
if [[ -n "$summary_only" ]]
then
    exit 0
fi
if [ $scenario_changed -eq 1 ] && [[ ! -n "$compose_only" ]]
then
    echo ""
    diff -u --label "$REPRO_DIFF_BASE_SCRIPT" --label "$(basename "$file")" "$tmp_dir/base_scenario" "$tmp_dir/model_scenario" | "${colorize[@]}" || true
fi
if [ $override_changed -eq 1 ]
then
    echo ""
    diff -u --label "$REPRO_DIFF_BASE_EXAMPLE/$REPRO_DIFF_BASE_OVERRIDE" --label "$REPRO_DIFF_MODEL_OVERRIDE" "$tmp_dir/base_override" "$tmp_dir/model_override" | "${colorize[@]}" || true
fi
