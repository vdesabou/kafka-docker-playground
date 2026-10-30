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

# jars are kept here, one folder per plugin version (or per zip), and reused on the next call
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

if [[ -n "$connector_zip" ]]
then
    if [[ $connector_zip == *"@"* ]]
    then
        connector_zip=${connector_zip#*@}
    fi
    if [[ "$connector_zip" != *.zip ]]
    then
        logerror "❌ --connector-zip $connector_zip is not a .zip file"
        exit 1
    fi
    zip_id=$(shasum "$connector_zip" | cut -c1-12)
    plugin_dir="$cache_root/zip-$(basename "$connector_zip" .zip)-$zip_id"
    label="$(basename "$connector_zip")"
    if [[ -n "$force_refresh" ]]
    then
        rm -rf "$plugin_dir"
    fi
    if [ ! -d "$plugin_dir" ]
    then
        search_jar_log "📦 Extracting $connector_zip"
        unzip -q "$connector_zip" -d "$tmp_dir/zip"
        mkdir -p "$plugin_dir"
        mv "$tmp_dir/zip"/* "$plugin_dir"/
    fi
else
    if [[ -n "$connector_tag" ]] && [ "$connector_tag" == " " ]
    then
        ret=$(choose_connector_tag "$connector_plugin")
        connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
    fi
    if [[ -z "$connector_tag" ]] || [ "$connector_tag" == "latest" ]
    then
        set +e
        connector_tag=$(playground connector-plugin versions --connector-plugin "$connector_plugin" --latest 2>/dev/null)
        set -e
        if [[ -z "$connector_tag" ]]
        then
            logwarn "could not find the latest version of $connector_plugin on Confluent Hub, its jars won't be cached"
            connector_tag="latest"
        fi
    fi
    label="$connector_plugin:$connector_tag"
    plugin_dir="$cache_root/$(echo "$connector_plugin" | tr '/' '-')-$connector_tag"
    if [[ -n "$force_refresh" ]] || [ "$connector_tag" == "latest" ]
    then
        rm -rf "$plugin_dir"
    fi
    if [ ! -d "$plugin_dir" ]
    then
        get_connect_image
        search_jar_log "🔌 Downloading connector plugin $connector_plugin:$connector_tag"
        mkdir -p "$tmp_dir/hub"
        # in a mktemp folder: Docker Desktop doesn't share /tmp (/private/tmp) by default
        if ! docker run -u0 -i --rm -v "$tmp_dir/hub:/usr/share/confluent-hub-components" ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c "confluent-hub install --no-prompt $connector_plugin:$connector_tag && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components" > "$tmp_dir/install.log" 2>&1
        then
            logerror "❌ could not download $connector_plugin:$connector_tag from Confluent Hub:"
            tail -5 "$tmp_dir/install.log"
            exit 1
        fi
        mkdir -p "$plugin_dir"
        mv "$tmp_dir/hub"/* "$plugin_dir"/
    else
        search_jar_log "♻️ Using the jars of $label already downloaded in $plugin_dir"
    fi
fi

lib_dir=$(find "$plugin_dir" -type d -name lib | head -1)
if [[ -z "$lib_dir" ]]
then
    # some zips have their jars at the top level
    lib_dir=$(dirname "$(find "$plugin_dir" -name '*.jar' | head -1)")
fi
if [[ -z "$lib_dir" ]] || [ "$lib_dir" == "." ]
then
    logerror "❌ no jar found in $plugin_dir"
    exit 1
fi

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
