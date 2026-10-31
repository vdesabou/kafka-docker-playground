# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
from="${args[--from]}"
to="${args[--to]}"
from_context="${args[--from-context]}"
to_context="${args[--to-context]}"
subject_prefix="${args[--subject-prefix]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

get_environment_used
if [[ "$environment" != mdc* ]]
then
    if [ -z "$from_context" ] && [ -z "$to_context" ]
    then
        logerror "❌ outside an mdc-* environment there is one registry: compare two contexts with --from-context / --to-context"
        exit 1
    fi
    from=""
    to=""
else
    from="${from:-europe}"
    to="${to:-us}"
fi
if [ "$from" == "$to" ] && [ "${from_context:-.}" == "${to_context:-.}" ]
then
    logerror "❌ --from and --to are the same registry and context"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

function export_side() {
    local cluster="$1"
    local context="$2"
    local dir="$3"
    local export_args=(-o "$dir")
    [ -n "$cluster" ] && export_args+=(--cluster "$cluster")
    [ -n "$context" ] && export_args+=(--context "$context")
    [ -n "$subject_prefix" ] && export_args+=(--subject-prefix "$subject_prefix")
    if ! playground schema export "${export_args[@]}" > "$dir.log" 2>&1
    then
        if grep -q "no subject to export" "$dir.log"
        then
            mkdir -p "$dir"
            echo '{"subjects": []}' > "$dir/manifest.json"
        else
            logerror "❌ can't read ${cluster:-the registry}${context:+ context $context}"
            cat "$dir.log"
            exit 1
        fi
    fi
}

left_label="${from:-registry}${from_context:+ context $from_context}"
right_label="${to:-registry}${to_context:+ context $to_context}"
[[ -n "$json" ]] || log "🔀 Comparing the subjects of ${left_label} and ${right_label}"
export_side "$from" "$from_context" "$tmp_dir/left"
export_side "$to" "$to_context" "$tmp_dir/right"
compare_args=(--left "$tmp_dir/left" --left-label "$left_label" --right "$tmp_dir/right" --right-label "$right_label")
[[ -n "$json" ]] && compare_args+=(--json)
python3 -I "$root_folder/tools/schema-tool/schema_compare.py" "${compare_args[@]}"
