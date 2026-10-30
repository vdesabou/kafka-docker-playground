connector_plugin="${args[--connector-plugin]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
class="${args[--class]}"
with_worker="${args[--with-worker]}"
json="${args[--json]}"
force_refresh="${args[--force-refresh]}"

if [[ $connector_plugin == *"@"* ]]
then
  connector_plugin=$(echo "$connector_plugin" | cut -d "@" -f 2)
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required"
    exit 1
fi

# jars are kept here, one folder per plugin version (or per zip), and reused on the next call (get_connector_plugin_lib_dir)
cache_root="/tmp/connector-plugin-jars"
mkdir -p "$cache_root"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

function search_jar_log () {
    # logs go to stderr with --json, so that stdout stays a JSON document
    if [[ -n "$json" ]]
    then
        log "$@" >&2
    else
        log "$@"
    fi
}

if [[ -z "$connector_plugin" ]] && [[ -z "$connector_zip" ]]
then
    logerror "❌ --connector-plugin or --connector-zip is required"
    exit 1
fi

if ! get_connector_plugin_lib_dir "$connector_plugin" "$connector_tag" "$connector_zip" "$force_refresh"
then
    exit 1
fi
lib_dir="$plugin_lib_dir"
label="$plugin_label"

jars_args=(--lib-dir "$lib_dir")
if [[ -n "$class" ]]
then
    jars_args+=(--class "$class")
    if command -v javap > /dev/null 2>&1 && javap -version > /dev/null 2>&1
    then
        jars_args+=(--javap javap)
    else
        search_jar_log "☕ no local JDK (javap): method signatures come from javap in a ${PG_JAVAP_IMAGE:-eclipse-temurin:21-jdk} container"
        jars_args+=(--javap docker)
    fi
fi

if [[ -n "$with_worker" ]]
then
    get_connect_image
    worker_index="$cache_root/worker-$(echo "${CP_CONNECT_IMAGE}" | tr '/' '_')-${CP_CONNECT_TAG}.tsv"
    if [[ -n "$force_refresh" ]]
    then
        rm -f "$worker_index"
    fi
    if [ ! -s "$worker_index" ]
    then
        search_jar_log "🧱 Indexing the classes of the worker classpath of ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} (once per image)"
        # the classpath is the one connect-distributed builds (a fake java prints it), the isolation
        # patterns come from PluginUtils of that worker
        docker run --rm --entrypoint bash ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} -c '
            mkdir -p /tmp/fj/bin
            printf "#!/bin/bash\nwhile [ \$# -gt 0 ]; do if [ \"\$1\" == \"-cp\" ]; then echo \"\$2\"; fi; shift; done\n" > /tmp/fj/bin/java
            chmod +x /tmp/fj/bin/java
            cp=$(JAVA_HOME=/tmp/fj connect-distributed /tmp/none.properties 2>/dev/null | head -1)
            for entry in ${cp//:/ }
            do
                for jar in $entry
                do
                    [ -f "$jar" ] && readlink -f "$jar"
                done
            done | grep "\.jar$" | sort -u > /tmp/jars
            while read -r jar
            do
                unzip -Z1 "$jar" 2>/dev/null | grep "\.class$" | grep -v "^META-INF/\|module-info\|package-info" | sed "s/\.class$//; s#/#.#g" | awk -v j="$jar" "{ print \$0 \"\t\" j }"
            done < /tmp/jars
            while read -r jar
            do
                if unzip -Z1 "$jar" 2>/dev/null | grep -q "^org/apache/kafka/connect/runtime/isolation/PluginUtils.class$"
                then
                    unzip -p "$jar" org/apache/kafka/connect/runtime/isolation/PluginUtils.class | grep -aoE "\^[ -~]{20,}\\$" | sed "s/^/PATTERN\t/"
                    break
                fi
            done < /tmp/jars
        ' > "$tmp_dir/worker.tsv" 2> "$tmp_dir/worker.err" || true
        if [ ! -s "$tmp_dir/worker.tsv" ]
        then
            logerror "❌ could not index the worker classpath of ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}"
            tail -5 "$tmp_dir/worker.err"
            exit 1
        fi
        mv "$tmp_dir/worker.tsv" "$worker_index"
    fi
    jars_args+=(--worker-index "$worker_index")
    if [[ -n "$class" ]]
    then
        # copies of the worker jars holding the class, for javap on the worker side
        worker_jars_dir="$cache_root/worker-jars-$(echo "${CP_CONNECT_IMAGE}" | tr '/' '_')-${CP_CONNECT_TAG}"
        mkdir -p "$worker_jars_dir"
        python3 -I "$root_folder/tools/connector-plugin-jars/jars.py" --lib-dir "$lib_dir" --class "$class" --worker-index "$worker_index" | jq -r '.worker_matches // [] | if length <= 5 then .[].jar else empty end' | sort -u > "$tmp_dir/worker_jars"
        while read -r jar
        do
            if [ ! -f "$worker_jars_dir/$(basename "$jar")" ]
            then
                docker run --rm --entrypoint cat ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} "$jar" > "$worker_jars_dir/$(basename "$jar")" 2>/dev/null || rm -f "$worker_jars_dir/$(basename "$jar")"
            fi
        done < "$tmp_dir/worker_jars"
        jars_args+=(--worker-jars-dir "$worker_jars_dir")
    fi
fi

if ! python3 -I "$root_folder/tools/connector-plugin-jars/jars.py" "${jars_args[@]}" > "$tmp_dir/result.json" 2> "$tmp_dir/stderr"
then
    logerror "❌ could not read the jars of $label: $(cat "$tmp_dir/stderr")"
    exit 1
fi
while IFS= read -r line
do
    [[ -n "$line" ]] && logwarn "$line"
done < "$tmp_dir/stderr"

if [[ -n "$json" ]]
then
    jq --arg label "$label" --arg image "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" '{plugin: $label} + . + (if .worker then {worker: (.worker + {image: $image})} else {} end)' "$tmp_dir/result.json"
    exit 0
fi

r="$tmp_dir/result.json"
log "🤎 $(jq '.jars | length' $r) jar(s), $(jq .nb_classes $r) classes in $lib_dir"
jq -r '.jars[]' $r

if [[ -n "$class" ]]
then
    nb_matches=$(jq '.matches | length' $r)
    if [ "$nb_matches" == "0" ]
    then
        logwarn "🤷 no class matching $class in the jars of $label"
    else
        if [ "$(jq -r .match_mode $r)" == "exact" ]
        then
            log "🔎 $nb_matches class(es) named $class in the jars of $label"
        else
            log "🔎 no class named exactly $class: $nb_matches class(es) contain it (case insensitive)"
        fi
        jq -r '.matches[] | "   👉 \(.class) in \(.jar)" + (if .loaded_from_worker == true then "   ⚠️ ignored: Connect loads this class from the worker" else "" end)' $r
        if [ "$nb_matches" -gt 5 ]
        then
            log "💡 method signatures are shown for 5 classes at most: give the simple name or the fully qualified name"
        fi
        jq -r '.matches[] | select(.signatures) | "\n☕ \(.class) (\(.jar)):\n\(.signatures)"' $r
    fi
    if [[ -n "$with_worker" ]]
    then
        nb_worker=$(jq '.worker_matches | length' $r)
        if [ "$nb_worker" == "0" ]
        then
            log "🧱 $class is not on the worker classpath of ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}"
        else
            log "🧱 $nb_worker class(es) matching $class on the worker classpath of ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}"
            jq -r '.worker_matches[] | "   👉 \(.class) in \(.jar)"' $r
            jq -r '.worker_matches[] | select(.signatures) | "\n☕ worker \(.class) (\(.jar | split("/") | last)):\n\(.signatures)"' $r
        fi
    fi
fi

if [[ -n "$with_worker" ]]
then
    nb_shadowed=$(jq '[.worker.shadowed[] | select(.same_jar | not) | .nb_classes] | add // 0' $r)
    if [ "$nb_shadowed" == "0" ]
    then
        log "✅ no class of the plugin is replaced by a different version from the worker ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}"
    else
        logwarn "⚠️ $nb_shadowed class(es) of the plugin are ignored: Connect loads them from the worker (org.apache.kafka.*, org.slf4j.*, java*…) in another version, a NoSuchMethodError / NoClassDefFoundError when the plugin needs its own"
        jq -r '.worker.shadowed[] | select(.same_jar | not) | "   ⚠️ \(.plugin_jar) ↔ worker \(.worker_jar | split("/") | last): \(.nb_classes) class(es), e.g. \(.example)"' $r
    fi
    jq -r '.worker.shadowed[] | select(.same_jar) | "   ✅ \(.plugin_jar): \(.nb_classes) class(es) loaded from the same jar of the worker"' $r
    nb_isolated=$(jq .worker.nb_isolated_duplicate_classes $r)
    if [ "$nb_isolated" != "0" ]
    then
        log "ℹ️ $nb_isolated other class(es) are on both sides: the plugin uses its own copy (plugin isolation), top jars:"
        jq -r '.worker.isolated_duplicates[0:5][] | "   • \(.plugin_jar) ↔ worker \(.worker_jar | split("/") | last): \(.nb_classes) class(es)"' $r
    fi
fi
