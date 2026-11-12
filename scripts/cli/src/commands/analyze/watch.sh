folder="${args[--folder]}"
output_dir="${args[--output-dir]}"
since="${args[--since]}"
once="${args[--once]}"
interval="${args[--interval]}"
no_open="${args[--no-open]}"
analyze_logs_args="${args[--analyze-logs-args]}"
eval "exclude_array=(${args[--exclude]})"
install_launch_agent="${args[--install-launch-agent]}"
uninstall_launch_agent="${args[--uninstall-launch-agent]}"
logs_only="${args[--logs-only]}"

launch_agent_label="io.kafka-docker-playground.analyze-watch"
launch_agent_plist="$HOME/Library/LaunchAgents/$launch_agent_label.plist"
launch_agent_log="$HOME/Library/Logs/playground-analyze-watch.log"

if [ -n "$install_launch_agent" ] || [ -n "$uninstall_launch_agent" ]
then
    if [[ "$OSTYPE" != "darwin"* ]]
    then
        logerror "❌ --install-launch-agent and --uninstall-launch-agent are for macOS (launchd)"
        exit 1
    fi
fi

if [ -n "$uninstall_launch_agent" ]
then
    launchctl bootout "gui/$(id -u)/$launch_agent_label" > /dev/null 2>&1 || true
    if [ -f "$launch_agent_plist" ]
    then
        rm -f "$launch_agent_plist"
        log "🗑️ LaunchAgent removed ($launch_agent_plist): the watch no longer starts at login"
    else
        log "✅ no LaunchAgent installed ($launch_agent_plist)"
    fi
    exit 0
fi

# a quoted "~/Downloads" is not expanded by the shell
expand_tilde() {
    case "$1" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

folder=$(expand_tilde "${folder:-$HOME/Downloads}")
output_dir=$(expand_tilde "${output_dir:-$HOME/playground-log-reports}")

if [ ! -d "$folder" ]
then
    logerror "❌ --folder $folder is not a folder"
    exit 1
fi
if ! ls "$folder" > /dev/null 2>&1
then
    logerror "❌ cannot read $folder"
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        logerror "💡 macOS protects ~/Downloads: allow your terminal in System Settings → Privacy & Security → Files and Folders (or Full Disk Access)"
    fi
    exit 1
fi
folder=$(cd "$folder" && pwd -P)
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd -P)
case "$output_dir/" in
    "$folder/"*)
        logerror "❌ --output-dir $output_dir is inside the watched folder $folder: each report would trigger a new analysis"
        exit 1
        ;;
esac
if [ "$interval" -lt 1 ]
then
    interval=1
fi

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

if [ -n "$install_launch_agent" ]
then
    if [ "$since" -gt 0 ] || [ -n "$once" ]
    then
        logwarn "⚠️ --since and --once are not kept in the LaunchAgent: it analyzes the entries that appear after each login"
    fi
    agent_args=("$root_folder/scripts/cli/playground" analyze watch --folder "$folder" --output-dir "$output_dir" --interval "$interval")
    for pattern in "${exclude_array[@]}"
    do
        agent_args+=(--exclude "$pattern")
    done
    if [ -n "$no_open" ]; then agent_args+=(--no-open); fi
    if [ -n "$logs_only" ]; then agent_args+=(--logs-only); fi
    if [ -n "$analyze_logs_args" ]; then agent_args+=(--analyze-logs-args "$analyze_logs_args"); fi
    mkdir -p "$(dirname "$launch_agent_plist")" "$(dirname "$launch_agent_log")"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0">'
        echo '<dict>'
        echo "    <key>Label</key><string>$launch_agent_label</string>"
        echo '    <key>ProgramArguments</key>'
        echo '    <array>'
        for a in "${agent_args[@]}"
        do
            echo "        <string>$(xml_escape "$a")</string>"
        done
        echo '    </array>'
        echo '    <key>EnvironmentVariables</key>'
        echo '    <dict>'
        # launchd starts jobs with a minimal PATH: the one of this shell finds bash 4+, python3, jq, mawk...
        echo "        <key>PATH</key><string>$(xml_escape "$PATH")</string>"
        echo "        <key>HOME</key><string>$(xml_escape "$HOME")</string>"
        echo "        <key>LANG</key><string>${LANG:-en_US.UTF-8}</string>"
        echo '    </dict>'
        echo '    <key>RunAtLoad</key><true/>'
        echo '    <key>KeepAlive</key><true/>'
        echo '    <key>ThrottleInterval</key><integer>60</integer>'
        echo '    <key>ProcessType</key><string>Background</string>'
        echo "    <key>StandardOutPath</key><string>$(xml_escape "$launch_agent_log")</string>"
        echo "    <key>StandardErrorPath</key><string>$(xml_escape "$launch_agent_log")</string>"
        echo '</dict>'
        echo '</plist>'
    } > "$launch_agent_plist"
    if ! plutil -lint "$launch_agent_plist" > /dev/null
    then
        logerror "❌ invalid LaunchAgent written: $launch_agent_plist"
        exit 1
    fi
    launchctl bootout "gui/$(id -u)/$launch_agent_label" > /dev/null 2>&1 || true
    if ! launchctl bootstrap "gui/$(id -u)" "$launch_agent_plist"
    then
        logerror "❌ launchctl bootstrap failed for $launch_agent_plist"
        exit 1
    fi
    log "✅ LaunchAgent installed and started: the watch of $folder now starts at every login, and restarts if it stops"
    log "📄 $launch_agent_plist"
    log "🪵 its output: tail -f $launch_agent_log"
    log "🗑️ to remove it: playground analyze watch --uninstall-launch-agent"
    log "🎓 it runs this checkout of the playground ($root_folder): keep it on a branch that has 'analyze watch'"
    exit 0
fi

extra_args=()
if [ -n "$analyze_logs_args" ]
then
    # split on spaces only, never evaluated
    read -r -a extra_args <<< "$analyze_logs_args"
fi

# the archive lister: bsdtar reads zip, tar (all compressions) and 7z; GNU tar and unzip otherwise
archive_list() {
    local path="$1"
    if command -v bsdtar > /dev/null 2>&1
    then
        bsdtar -tf "$path" 2> /dev/null
        return
    fi
    case "$path" in
        *.zip|*.ZIP) unzip -Z1 "$path" 2> /dev/null ;;
        *.7z) if command -v 7zz > /dev/null 2>&1; then 7zz l -ba -slt "$path" 2> /dev/null | sed -n 's/^Path = //p'; elif command -v 7z > /dev/null 2>&1; then 7z l -ba -slt "$path" 2> /dev/null | sed -n 's/^Path = //p'; fi ;;
        *) tar -tf "$path" 2> /dev/null ;;
    esac
}

# one entry of an archive on stdout, nothing written on disk
archive_cat() {
    local path="$1" entry="$2"
    if command -v bsdtar > /dev/null 2>&1
    then
        bsdtar -xOf "$path" "$entry" 2> /dev/null
        return
    fi
    case "$path" in
        *.zip|*.ZIP) unzip -p "$path" "$entry" 2> /dev/null ;;
        *.7z) if command -v 7zz > /dev/null 2>&1; then 7zz x -so "$path" "$entry" 2> /dev/null; elif command -v 7z > /dev/null 2>&1; then 7z x -so "$path" "$entry" 2> /dev/null; fi ;;
        *) tar -xOf "$path" "$entry" 2> /dev/null ;;
    esac
}

# names that are log files: server.log, connect.log.3, kafka.log.gz, stdout, gc.log.0.current, logs/<anything>, .out
log_name_regex='(\.log(\.[0-9]+)?(\.gz)?$|\.log\.[0-9-]+(\.gz)?$|\.out(\.[0-9]+)?$|(^|/)(stdout|stderr)(\.txt)?$|log[^/]*\.txt$|(^|/)logs?/[^/]+[^/]$|\.(jsonl|ndjson)(\.gz)?$|gc[^/]*\.current$|\.(zip|tgz|tar|tar\.gz|tar\.bz2|tar\.xz|7z)$)'
# the files of another analyzer (heap dumps, flight recordings, network captures, XStream reports, thread dumps): an
# archive or a folder holding only them is analyzed too (analyze logs keeps them in <stem>-other-files/)
other_name_regex='(\.hprof(\.gz)?$|\.jfr$|\.(pcap|pcapng|cap)(\.gz)?$|orclcdc[^/]*\.html?$|(thread|jstack)[^/]*$)'

# lines that look like log records: a time and a level, librdkafka (%3|1793896102.923|FAIL|...), JSON with a level, logfmt
time_regex='[0-9]{2}:[0-9]{2}:[0-9]{2}|"@?timestamp"|[0-9]{10}\.[0-9]{3}'
level_regex='(^|[^A-Za-z])(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|SEVERE)([^A-Za-z]|$)|"(level|severity)" *: *"|level=(trace|debug|info|warn|warning|error|fatal)|^%[0-7]\|[0-9]+\.[0-9]+\|'

# reads stdin (the first 64 KB), true when at least 3 lines look like log records
looks_like_logs() {
    local nb
    nb=$(head -c 65536 | LC_ALL=C tr -d '\000' | LC_ALL=C grep -aE "$time_regex" | LC_ALL=C grep -acE "$level_regex")
    [ "${nb:-0}" -ge 3 ]
}

# the content of a file, decompressed, the text of a Word / Excel document
file_text() {
    local path="$1"
    case "$path" in
        *.gz) gzip -dc "$path" 2> /dev/null ;;
        *.docx) unzip -p "$path" word/document.xml 2> /dev/null | awk '{ gsub(/<\/w:p>/, "\n"); gsub(/<[^>]*>/, ""); print }' ;;
        *.xlsx|*.xlsm) unzip -p "$path" xl/sharedStrings.xml 2> /dev/null | awk '{ gsub(/<\/si>/, "\n"); gsub(/<[^>]*>/, ""); print }' ;;
        *) cat "$path" 2> /dev/null ;;
    esac
}

# a file worth sniffing: text-like extensions, or none at all
sniffable_name() {
    local base
    base=$(basename "$1")
    base="${base%.gz}"
    case "$base" in
        *.txt|*.TXT|*.json|*.csv|*.out|*.docx|*.xlsx|*.xlsm|*.yaml|*.yml) return 0 ;;
        *.*) return 1 ;;
        *) return 0 ;;
    esac
}

# prints "logs<TAB>reason" when the entry holds logs, "others<TAB>reason" when it only holds the files of other analyzers
# (heap dumps, captures…), nothing (false) otherwise
holds_logs() {
    local path="$1" name nb f
    name=$(basename "$path")
    if [ -d "$path" ]
    then
        nb=$(find "$path" -type f ! -name '.*' 2> /dev/null | head -20000 | LC_ALL=C grep -acE "$log_name_regex")
        if [ "${nb:-0}" -gt 0 ]
        then
            printf 'logs\t%s\n' "folder with $nb log file(s) or archive(s)"
            return 0
        fi
        # no log file name: sniff the first text-like files
        nb=0
        while IFS= read -r -d '' f
        do
            sniffable_name "$f" || continue
            nb=$((nb + 1))
            if file_text "$f" | looks_like_logs
            then
                printf 'logs\t%s\n' "folder with log records ($(basename "$f"))"
                return 0
            fi
            [ $nb -ge 50 ] && break
        done < <(find "$path" -type f ! -name '.*' -size -200000k -print0 2> /dev/null)
        if [ -z "$logs_only" ]
        then
            nb=$(find "$path" -type f ! -name '.*' 2> /dev/null | head -20000 | LC_ALL=C grep -aicE "$other_name_regex")
            if [ "${nb:-0}" -gt 0 ]
            then
                printf 'others\t%s\n' "folder with $nb dump(s), capture(s) or report(s), no logs"
                return 0
            fi
        fi
        return 1
    fi
    case "$name" in
        *.zip|*.ZIP|*.tar|*.tgz|*.tar.gz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz|*.7z)
            nb=$(archive_list "$path" | LC_ALL=C grep -acE "$log_name_regex")
            if [ "${nb:-0}" -gt 0 ]
            then
                printf 'logs\t%s\n' "archive with $nb log file(s) or archive(s)"
                return 0
            fi
            # no log file name: sniff the first text-like entries
            nb=0
            while IFS= read -r f
            do
                case "$f" in */|*/.*|.*) continue ;; esac
                sniffable_name "$f" || continue
                case "$f" in *.gz|*.docx|*.xlsx|*.xlsm) continue ;; esac
                nb=$((nb + 1))
                if archive_cat "$path" "$f" | looks_like_logs
                then
                    printf 'logs\t%s\n' "archive with log records ($(basename "$f"))"
                    return 0
                fi
                [ $nb -ge 10 ] && break
            done < <(archive_list "$path")
            if [ -z "$logs_only" ]
            then
                nb=$(archive_list "$path" | LC_ALL=C grep -aicE "$other_name_regex")
                if [ "${nb:-0}" -gt 0 ]
                then
                    printf 'others\t%s\n' "archive with $nb dump(s), capture(s) or report(s), no logs"
                    return 0
                fi
            fi
            return 1
            ;;
    esac
    if printf '%s\n' "$name" | LC_ALL=C grep -qE "$log_name_regex"
    then
        printf 'logs\t%s\n' "log file"
        return 0
    fi
    if sniffable_name "$path" && file_text "$path" | looks_like_logs
    then
        printf 'logs\t%s\n' "file with log records"
        return 0
    fi
    return 1
}

# size of a file or a folder, to know when a download is complete
entry_size() {
    if [ -d "$1" ]
    then
        { find "$1" -type f 2> /dev/null | wc -l; du -sk "$1" 2> /dev/null | cut -f1; } | tr '\n' ' '
    else
        wc -c < "$1" 2> /dev/null | tr -d ' '
    fi
}

# a download in progress: the temporary names of Chrome / Edge, Safari, Firefox, and the final name Firefox creates
# empty next to its .part
is_in_progress() {
    local name="$1"
    case "$name" in
        *.crdownload|*.download|*.part|*.partial|*.tmp|*.opdownload|"Unconfirmed "*) return 0 ;;
    esac
    [ -e "$folder/$name.part" ] || [ -e "$folder/$name.crdownload" ] || [ -e "$folder/$name.download" ]
}

notify() {
    if [[ "$OSTYPE" == "darwin"* ]] && command -v osascript > /dev/null 2>&1
    then
        # the message is an argument, never part of the AppleScript source (file names are untrusted)
        osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "kafka-docker-playground"' -e 'end run' "$1" > /dev/null 2>&1 || true
    fi
}

archive_stem() {
    local name="$1"
    # the tar ones before .gz / .bz2 / .xz: x.tar.gz is x, x.hprof.gz is x.hprof (what Archive Utility extracts)
    for ext in .tar.gz .tar.bz2 .tar.xz .zip .ZIP .tgz .tbz2 .txz .tar .7z .gz .bz2 .xz
    do
        case "$name" in
            *"$ext") printf '%s\n' "${name%"$ext"}"; return ;;
        esac
    done
    printf '%s\n' "$name"
}

declare -A seen=()      # entries already handled (or there at the start)
declare -A pending=()   # name -> last size seen
declare -A stable=()    # name -> number of checks with the same size
declare -A analyzed_stems=()
nb_analyzed=0

# kind<TAB>path of the files given (label<TAB>path on stdin), from the classifier of the 🧰 Other files of analyze logs
# (tools/log-analyzer/bundle_triage.py). One line of python: bashly indents the partial, a multi-line -c would break: gc_log, thread_dump, heap_dump, flight_recording, network_capture, xstream_report,
# topic_describe, log_dirs, screenshot, document. Nothing is copied or moved (no --keep-dir)
triage_kinds() {
    local walked
    walked=$(mktemp -t kdp-watch-walked)
    cat > "$walked"
    python3 -I "$root_folder/tools/log-analyzer/bundle_triage.py" --walked "$walked" 2> /dev/null \
        | python3 -I -c 'import json, sys; [print(f["kind"] + "\t" + f["path"]) for f in json.load(sys.stdin).get("files", []) if f.get("path") and "\t" not in f["path"] and "\n" not in f["path"]]' 2> /dev/null
    rm -f "$walked"
}

# the analyzer of a kind ("" when analyze logs reads it itself, or nothing does)
analyzer_of() {
    case "$1" in
        gc_log) echo gc-logs ;;
        thread_dump) echo thread-dump ;;
        heap_dump) echo heap-dump ;;
        flight_recording) echo flight-recorder ;;
        network_capture) echo tcp-dump ;;
        xstream_report) echo oracle-xstream-report ;;
        *) echo "" ;;
    esac
}

# runs 'playground analyze <analyzer> <args>' with its report in $report_dir, opened (or not) in the browser
run_analyzer() {
    local label="$1" analyzer="$2" rc=0 report before
    shift 2
    before=$(ls -t "$report_dir"/*-report.html 2> /dev/null | head -1)
    if [ -n "$no_open" ] || [ -n "${quiet_run:-}" ]
    then
        # stdout not a terminal: the report is not opened
        (unset PLAYGROUND_RUN_LOG_TERMINAL; playground analyze "$analyzer" "$@" --output-dir "$report_dir" | cat) || rc=$?
    elif [[ -t 1 ]]
    then
        playground analyze "$analyzer" "$@" --output-dir "$report_dir" || rc=$?
    else
        PLAYGROUND_RUN_LOG_TERMINAL=1 playground analyze "$analyzer" "$@" --output-dir "$report_dir" || rc=$?
    fi
    report=$(ls -t "$report_dir"/*-report.html 2> /dev/null | head -1)
    if [ $rc -ne 0 ]
    then
        logwarn "⚠️ $label: playground analyze $analyzer exited with $rc"
        notify "⚠️ analyze $analyzer of $label failed ($rc)"
    elif [ -n "$report" ] && [ "$report" != "$before" ]
    then
        log "📊 $label: $report"
        if [ -z "${quiet_run:-}" ]; then notify "📊 Report ready: $label ($analyzer)"; fi
    fi
}

# the dedicated analyzers on the files of an archive (kept by analyze logs in <stem>-other-files/) or of a folder:
# one run per kind (one per file for heap-dump, which reads one), thread dumps left out (analyzed in the logs report)
run_other_analyzers() {
    local label="$1" source="$2" kind path analyzer
    declare -A kind_files=()
    while IFS=$'\t' read -r kind path
    do
        [ "$kind" = "thread_dump" ] && continue
        analyzer=$(analyzer_of "$kind")
        [ -n "$analyzer" ] || continue
        if [ "$kind" = "heap_dump" ]
        then
            log "🔬 $label: heap dump $(basename "$path"), running playground analyze heap-dump (Eclipse MAT in Docker, can take minutes)"
            run_analyzer "$label" heap-dump -f "$path"
            continue
        fi
        kind_files[$kind]+="$path"$'\n'
    done < <(find "$source" -type f ! -name '.*' 2> /dev/null | head -2000 | awk '{ n = $0; sub(/.*\//, "", n); print n "\t" $0 }' | triage_kinds)
    for kind in gc_log flight_recording network_capture xstream_report
    do
        [ -n "${kind_files[$kind]:-}" ] || continue
        local files=() f_args=()
        mapfile -t files < <(printf '%s' "${kind_files[$kind]}" | head -20)
        for path in "${files[@]}"
        do
            f_args+=(-f "$path")
        done
        analyzer=$(analyzer_of "$kind")
        log "🧰 $label: ${#files[@]} $kind file(s), running playground analyze $analyzer"
        run_analyzer "$label" "$analyzer" "${f_args[@]}"
    done
}

# ⚠️ errexit is on in the generated CLI: no function may end on a false test ([ … ] && …), it would stop the watch
# an archive or a compressed file analyzed: what Safari or Archive Utility extracts from it next to it (x.zip → x/,
# x.hprof.gz → x.hprof or x.hprof/) is not analyzed again. Only when the name changes: a c.log deleted then downloaded
# again is a new download
record_analyzed() {
    local stem
    stem=$(archive_stem "$1")
    if [ "$stem" != "$1" ]; then analyzed_stems[$stem]="$1"; fi
    nb_analyzed=$((nb_analyzed + 1))
    return 0
}

analyze_entry() {
    local name="$1" path="$folder/$1" reason holds stem kind analyzer
    if [ -n "${analyzed_stems[$name]:-}" ]
    then
        log "⏭️  $name: extracted from ${analyzed_stems[$name]}, already analyzed"
        return 0
    fi
    stem=$(printf '%s' "$(archive_stem "$name")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
    report_dir="$output_dir/${stem}-$(date +%Y%m%d-%H%M%S)"

    # a single file of another analyzer: a heap dump, a flight recording, a capture, an XStream report, a GC log or a
    # thread dump (a log file holding a kill -3 thread dump stays a log file: analyze logs analyzes the dump in its report)
    if [ -f "$path" ] && [ -z "$logs_only" ]
    then
        kind=$(printf '%s\t%s\n' "$name" "$path" | triage_kinds | cut -f1)
        analyzer=$(analyzer_of "$kind")
        if [ -n "$analyzer" ] && { { [ "$kind" != "gc_log" ] && [ "$kind" != "thread_dump" ]; } || ! file_text "$path" | looks_like_logs; }
        then
            mkdir -p "$report_dir"
            log "🧰 $name: $kind, running playground analyze $analyzer (report in $report_dir)"
            notify "🧰 Analyzing $name ($analyzer)"
            run_analyzer "$name" "$analyzer" -f "$path"
            record_analyzed "$name"
            return 0
        fi
    fi

    if ! holds=$(holds_logs "$path")
    then
        log "🙈 $name: no logs, dumps, captures or reports found, ignored"
        return 0
    fi
    reason="${holds#*$'\t'}"
    mkdir -p "$report_dir"
    if [ "${holds%%$'\t'*}" = "others" ]
    then
        notify "🧰 Analyzing $name"
        if [ -d "$path" ]
        then
            log "🧰 $name: $reason, running their analyzers (reports in $report_dir)"
            run_other_analyzers "$name" "$path"
        else
            # analyze logs extracts them (<stem>-other-files/): its report, without logs, is neither opened nor notified
            log "🧰 $name: $reason, extracted by playground analyze logs (report not opened), then their analyzers (reports in $report_dir)"
            quiet_run=1 run_analyzer "$name" logs -f "$path" "${extra_args[@]}"
            for kept in "$report_dir"/*-other-files
            do
                if [ -d "$kept" ]; then run_other_analyzers "$name" "$kept"; fi
            done
        fi
        record_analyzed "$name"
        return 0
    fi
    log "🔥 $name: $reason, running playground analyze logs (report in $report_dir)"
    notify "🔥 Analyzing $name"
    run_analyzer "$name" logs -f "$path" "${extra_args[@]}"
    record_analyzed "$name"

    if [ -z "$logs_only" ]
    then
        if [ -d "$path" ]
        then
            run_other_analyzers "$name" "$path"
        else
            for kept in "$report_dir"/*-other-files
            do
                if [ -d "$kept" ]; then run_other_analyzers "$name" "$kept"; fi
            done
        fi
    fi
    return 0
}

# the entries of the folder, NUL separated, hidden ones left out (.DS_Store, .localized)
list_entries() {
    find "$folder" -mindepth 1 -maxdepth 1 ! -name '.*' -print0 2> /dev/null
}

# the console log of the watcher itself (the LaunchAgent writes ~/Library/Logs/playground-analyze-watch.log), copied or
# downloaded into the folder ("playground-analyze-watch (1).log" too): it only quotes the digests of the files it
# analyzed, analyzing it again gives a report of a report
is_own_log() {
    [[ "$1" == playground-analyze-watch*.log* ]]
}

# --exclude: top-level names (wildcards allowed) never analyzed, whatever happens to them (moved, renamed, re-created)
is_excluded() {
    local pattern
    is_own_log "$1" && return 0
    for pattern in "${exclude_array[@]}"
    do
        # shellcheck disable=SC2053
        [[ "$1" == $pattern ]] && return 0
    done
    return 1
}

# creation time of an entry (epoch seconds), its modification time when the file system does not keep it: a folder
# you move files into (~/Downloads/Archives) gets a new modification time, never a new creation time
entry_birth() {
    local t
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        t=$(stat -f %B "$1" 2> /dev/null)
    else
        t=$(stat -c %W "$1" 2> /dev/null)
    fi
    if [ -z "$t" ] || [ "$t" -le 0 ] 2> /dev/null
    then
        if [[ "$OSTYPE" == "darwin"* ]]; then t=$(stat -f %m "$1" 2> /dev/null); else t=$(stat -c %Y "$1" 2> /dev/null); fi
    fi
    printf '%s\n' "${t:-0}"
}

# start: everything already there is seen, except what --since picks (created in the last minutes)
since_epoch=$(( $(date +%s) - since * 60 ))
while IFS= read -r -d '' p
do
    name=$(basename "$p")
    if [ "$since" -gt 0 ] && ! is_excluded "$name" && [ "$(entry_birth "$p")" -ge "$since_epoch" ]
    then
        continue
    fi
    seen["$name"]=1
done < <(list_entries)

trap 'echo; log "👋 stopped watching $folder ($nb_analyzed analyzed)"; exit 0' INT TERM

if [ -n "$once" ]
then
    log "🔎 analyzing the entries of $folder created in the last $since minute(s)"
else
    log "👀 watching $folder for new logs, dumps, captures and reports (every ${interval}s, reports in $output_dir), Ctrl-C to stop"
fi

while true
do
    declare -A present=()
    while IFS= read -r -d '' p
    do
        name=$(basename "$p")
        present["$name"]=1
        [ -n "${seen[$name]:-}" ] && continue
        if is_own_log "$name"
        then
            log "🚫 $name: the log of playground analyze watch itself, ignored"
            seen["$name"]=1
            continue
        elif is_excluded "$name"
        then
            log "🚫 $name: excluded (--exclude), ignored"
            seen["$name"]=1
            continue
        fi
        if is_in_progress "$name"
        then
            continue
        fi
        size=$(entry_size "$p")
        if [ "$size" = "0" ]
        then
            continue
        fi
        if [ -n "$once" ]
        then
            pending["$name"]="$size"
            stable["$name"]=2
        elif [ "${pending[$name]:-}" = "$size" ]
        then
            stable["$name"]=$(( ${stable[$name]:-0} + 1 ))
        else
            if [ -z "${pending[$name]:-}" ]; then log "⏳ new entry: $name"; fi
            pending["$name"]="$size"
            stable["$name"]=0
        fi
    done < <(list_entries)

    # complete (same size for 2 checks): archives first, so that a folder Safari extracts from a zip is skipped
    ready=()
    for name in "${!pending[@]}"
    do
        if [ -z "${present[$name]:-}" ]
        then
            unset 'pending[$name]' 'stable[$name]'
        elif [ "${stable[$name]}" -ge 2 ]
        then
            ready+=("$name")
        fi
    done
    for pass in archive other
    do
        for name in "${ready[@]}"
        do
            if [ -d "$folder/$name" ]; then kind=other; else kind=archive; fi
            [ "$kind" = "$pass" ] || continue
            seen["$name"]=1
            unset 'pending[$name]' 'stable[$name]'
            analyze_entry "$name"
        done
    done

    # an entry deleted, then downloaded again with the same name, is a new one
    for name in "${!seen[@]}"
    do
        if [ -z "${present[$name]:-}" ]; then unset 'seen[$name]'; fi
    done
    unset present

    if [ -n "$once" ]
    then
        if [ $nb_analyzed -eq 0 ]; then log "✅ nothing to analyze in $folder (last $since minute(s))"; fi
        break
    fi
    sleep "$interval"
done
