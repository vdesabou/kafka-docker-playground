query="${args[query]}"
list="${args[--list]}"
json="${args[--json]}"
last="${args[--last]}"
run="${args[--run]}"
limit="${args[--limit]}"
all="${args[--all]}"
stats="${args[--stats]}"
prune="${args[--prune]}"

if [ ${#other_args[@]} -gt 0 ]
then
    query="$query ${other_args[*]}"
fi
if [[ -n "$json" ]]
then
    list=1
fi

history_file="$root_folder/playground-run-history"
if [ ! -f "$history_file" ]
then
    logerror "❌ history could not be found !"
    logerror "$history_file does not exist"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# value of a key of the trailing comment of a run: date=… branch=… result=… duration=…
# (into the variable named by $3 when given: no subshell in the loop over the whole history)
function history_meta () {
    local history_meta_comment=" $1" history_meta_value=""
    if [[ "$history_meta_comment" == *" $2="* ]]
    then
        history_meta_value="${history_meta_comment##* $2=}"
        history_meta_value="${history_meta_value%% *}"
    fi
    if [ -n "$3" ]
    then
        printf -v "$3" '%s' "$history_meta_value"
    else
        echo "$history_meta_value"
    fi
}

function history_duration () {
    local seconds="$1"
    if [ -z "$seconds" ]
    then
        return
    fi
    if [ "$seconds" -ge 3600 ]
    then
        echo "$((seconds / 3600))h$((seconds % 3600 / 60))m"
    elif [ "$seconds" -ge 60 ]
    then
        echo "$((seconds / 60))m$((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

function history_result_icon () {
    local history_icon
    case "$1" in
        SUCCESS) history_icon="✅" ;;
        FAILURE) history_icon="❌" ;;
        SKIPPED) history_icon="⏭️" ;;
        INTERRUPTED) history_icon="⏹️" ;;
        *) history_icon="▫️" ;;
    esac
    if [ -n "$2" ]
    then
        printf -v "$2" '%s' "$history_icon"
    else
        echo "$history_icon"
    fi
}

function history_mask_creds () {
    if [[ "$1" == *"creds"* ]]
    then
        # a value is a word, backslash-quoted characters included
        sed -E 's/(--cluster-(schema-registry-)?creds[ =])([^ \\]|\\.)+/\1'"'<masked>'"'/g' <<< "$1"
    else
        echo "$1"
    fi
}

# tac is GNU coreutils: not on macOS without Homebrew
function history_reverse () {
    awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$@"
}

# most recent first, de-duplicated on the command (spaces normalized, so that a trailing space is not another
# entry): "<command> US <comment of its last run> US <number of runs>" (US: unit separator, not a
# whitespace like TAB, so that read keeps an empty field)
history_reverse "$history_file" | awk '
    { gsub(/[ \t]+/, " "); sub(/^ /, ""); sub(/ $/, "") }
    !/^playground run -f / { next }
    {
        command = $0; meta = ""
        i = index($0, " # date=")
        if (i > 0) { command = substr($0, 1, i - 1); meta = substr($0, i + 3) }
        if (!(command in runs)) { order[++n] = command; last_meta[command] = meta }
        runs[command]++
    }
    END { for (i = 1; i <= n; i++) print order[i] "\037" last_meta[order[i]] "\037" runs[order[i]] }' > $tmp_dir/history

if [[ -n "$stats" ]]
then
    nb_runs=$(awk -F '\037' '{ total += $3 } END { print total + 0 }' $tmp_dir/history)
    log "📊 $nb_runs runs of $(wc -l < $tmp_dir/history | tr -d ' ') different commands in $history_file"
    log "🏆 most run examples"
    awk -F '\037' -v root="$root_folder/" '{
            script = substr($1, length("playground run -f ") + 1)
            gsub(/\\ /, "\001", script); sub(/ .*/, "", script); gsub(/\001/, " ", script); gsub(/\\/, "", script)
            if (index(script, root) == 1) script = substr(script, length(root) + 1)
            runs[script] += $3
        }
        END { for (s in runs) printf "%6d  %s\n", runs[s], s }' $tmp_dir/history | sort -rn | head -10
    for key in tag connector-tag environment
    do
        log "🏷️ --$key"
        grep -oE -- "--$key=[^ ]+" "$history_file" | cut -d "=" -f 2- | sort | uniq -c | sort -rn | head -5
    done
    log "🚦 results (runs recorded since the results are kept)"
    grep -oE " result=[A-Z]+" "$history_file" | cut -d "=" -f 2 | sort | uniq -c | sort -rn
    exit 0
fi

# one "<displayed line> US <command> US <script> US <comment> US <runs>" per entry matching the query whose
# script still exists (--all: every entry): the root folder is not displayed, nor the credentials written in clear
# by older versions
nb_missing=0
query_words=()
if [[ -n "$list" ]] || [[ -n "$last" ]] || [[ -n "$run" ]]
then
    # the picker gets the query as its initial query instead
    read -r -a query_words <<< "${query,,}"
fi
: > $tmp_dir/entries
while IFS=$'\x1f' read -r command meta runs
do
    lower="${command,,}"
    matching=1
    for word in "${query_words[@]}"
    do
        if [[ "$lower" != *"$word"* ]]
        then
            matching=0
            break
        fi
    done
    if [ $matching -eq 0 ]
    then
        continue
    fi
    # the script path ends at the first space that is not backslash-quoted
    script="${command#playground run -f }"
    script="${script//\\ /$'\x01'}"
    script="${script%% *}"
    script="${script//\\/}"
    script="${script//$'\x01'/ }"
    history_meta "$meta" result result
    history_result_icon "$result" icon
    if [ ! -f "$script" ]
    then
        nb_missing=$((nb_missing+1))
        if [[ -z "$all" ]] || [[ -n "$prune" ]]
        then
            continue
        fi
        icon="🗑️"
    fi
    history_meta "$meta" date date
    date="${date/T/ }"
    displayed="${command//"$root_folder/"/}"
    if [[ "$displayed" == *"creds"* ]]
    then
        displayed=$(history_mask_creds "$displayed")
    fi
    # fzf counts these emojis (with a variation selector) as one column, the terminal draws two
    case "$icon" in
        ⏭️|⏹️|🗑️) icon+=" " ;;
    esac
    # no date column for the runs recorded before the dates were kept: just the icon
    if [ -n "$date" ]
    then
        icon+=" ${date:0:16} "
    fi
    printf '%s %s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$icon" "${displayed#playground run -f }" "$command" "$script" "$meta" "$runs" >> $tmp_dir/entries
done < $tmp_dir/history

if [[ -n "$prune" ]]
then
    nb_lines=$(wc -l < "$history_file" | tr -d ' ')
    cp "$history_file" "$history_file.bak"
    # oldest first, as run appends them
    history_reverse $tmp_dir/entries | awk -F '\037' '{ print $2 ($4 != "" ? " # " $4 : "") }' > "$history_file"
    log "🧹 $history_file: $nb_lines lines → $(wc -l < "$history_file" | tr -d ' ') (one per command, $nb_missing whose script no longer exists removed)"
    log "💾 previous version kept in $history_file.bak"
    exit 0
fi

if [ $nb_missing -gt 0 ] && [[ -z "$all" ]] && [[ -z "$json" ]] && [[ -z "$last" ]]
then
    log "🙈 $nb_missing entries not shown: their script no longer exists (--all to show them)"
fi

if [ ! -s $tmp_dir/entries ]
then
    if [[ -n "$json" ]]
    then
        echo "[]"
    else
        logerror "❌ no run to show in $history_file${query:+ matching \"$query\"}"
    fi
    exit 1
fi

# the credentials are not kept in the history: take them from playground.ini if it is the same cluster
function history_unmask_creds () {
    local res="$1"
    if [[ "$res" == *"'<masked>'"* ]]
    then
        if [[ "$res" =~ --cluster-name[\ =]([^ ]+) ]] && [ "${BASH_REMATCH[1]}" == "$(playground state get ccloud.CLUSTER_NAME)" ]
        then
            res="${res//"--cluster-creds '<masked>'"/--cluster-creds $(printf '%q' "$(playground state get ccloud.CLUSTER_CREDS)")}"
            res="${res//"--cluster-schema-registry-creds '<masked>'"/--cluster-schema-registry-creds $(printf '%q' "$(playground state get ccloud.SCHEMA_REGISTRY_CREDS)")}"
        else
            logerror "❌ the credentials of this run are not kept in the history, and its cluster is not the one of playground.ini"
            logerror "👉 run it with 'playground history' and replace '<masked>' by the credentials"
            return 1
        fi
    fi
    echo "$res"
}

if [[ -n "$last" ]]
then
    head -1 $tmp_dir/entries | cut -d $'\x1f' -f 2
    exit 0
fi

if [[ -n "$run" ]]
then
    res=$(history_unmask_creds "$(head -1 $tmp_dir/entries | cut -d $'\x1f' -f 2)") || exit 1
    log "🏰 $(history_mask_creds "$res")"
    eval "$res"
    exit $?
fi

if [[ -n "$list" ]]
then
    if [ "$limit" != "0" ]
    then
        head -n "$limit" $tmp_dir/entries > $tmp_dir/listed
    else
        cp $tmp_dir/entries $tmp_dir/listed
    fi
    if [[ -n "$json" ]]
    then
        while IFS=$'\x1f' read -r displayed command script meta runs
        do
            exists=false
            [ -f "$script" ] && exists=true
            printf '%s\t%s\t%s\t%s\t%s\n' "$(history_mask_creds "$command")" "$script" "$meta" "$runs" "$exists"
        done < $tmp_dir/listed | jq -R -s --arg root "$root_folder/" '
            split("\n") | map(select(length > 0) | split("\t") | . as $f
                | ($f[2] | split(" ") | map(select(contains("=")) | {key: (split("=")[0]), value: (split("=")[1:] | join("="))}) | from_entries) as $m
                | {command: $f[0], script: $f[1], path: ($f[1] | ltrimstr($root)), exists: ($f[4] == "true"),
                   date: $m.date, result: $m.result, duration_seconds: ($m.duration | if . then tonumber else null end),
                   branch: $m.branch, runs: ($f[3] | tonumber)})'
        exit 0
    fi
    log "🏰 runs${query:+ matching \"$query\"}, most recent first"
    while IFS=$'\x1f' read -r displayed command script meta runs
    do
        echo "$(history_mask_creds "$command")"
        details=()
        result=$(history_meta "$meta" result)
        date=$(history_meta "$meta" date)
        duration=$(history_duration "$(history_meta "$meta" duration)")
        branch=$(history_meta "$meta" branch)
        if [ ! -f "$script" ]
        then
            details+=("🗑️ script no longer exists")
        elif [ -n "$result" ]
        then
            details+=("$(history_result_icon "$result") $result")
        fi
        [ -n "$date" ] && details+=("${date/T/ }")
        [ -n "$duration" ] && details+=("$duration")
        [ -n "$branch" ] && details+=("$branch")
        details+=("$runs run(s)")
        joined=$(printf ' · %s' "${details[@]}")
        echo "    ${joined:3}"
    done < $tmp_dir/listed
    exit 0
fi

fzf_version=$(get_fzf_version)
if version_gt $fzf_version "0.38"
then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
fi

# preview: last result, README title, the header of a repro model, the command
{
    printf 'root_folder=%q\n' "$root_folder"
    declare -f history_meta history_duration history_result_icon history_mask_creds
    cat << 'EOF'
command="$1"; script="$2"; meta="$3"; runs="$4"
echo "📄 ${script#"$root_folder/"}"
[ -f "$script" ] || echo "🗑️ the script no longer exists"
result=$(history_meta "$meta" result)
date=$(history_meta "$meta" date)
if [ -n "$date" ]
then
    line="🕰️ ${date/T/ }"
    [ -n "$result" ] && line+="  $(history_result_icon "$result") $result"
    duration=$(history_duration "$(history_meta "$meta" duration)")
    [ -n "$duration" ] && line+=" in $duration"
    branch=$(history_meta "$meta" branch)
    [ -n "$branch" ] && line+="  🌿 $branch"
    echo "$line"
fi
echo "🔁 $runs run(s) of this command"
title=$(grep -m 1 "^# " "$(dirname "$script")/README.md" 2> /dev/null)
[ -n "$title" ] && echo "📖 ${title#\# }"
grep -E "^# (💡 description|🎯 expected|💥 actual|🎫 jira|🩹 status): ?[^ ]" "$script" 2> /dev/null | sed -e 's/^# //'
echo
history_mask_creds "$command"
EOF
} > $tmp_dir/preview.sh

res=$(cat $tmp_dir/entries | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🏰" --header="ctrl-c or esc to quit · ✅ success ❌ failure ⏭️  skipped ⏹️  interrupted" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter $'\x1f' --with-nth 1 --query "$query" --preview "bash $tmp_dir/preview.sh {2} {3} {4} {5}" $fzf_option_wrap $fzf_option_pointer | cut -d $'\x1f' -f 2)
if [ -z "$res" ]
then
    exit 0
fi

# tab in the edit prompt: read -e only completes file names, ask the CLI for the completions of the shell
# (playground __complete, what completions.bash and completions.zsh call)
function history_complete () {
    local before="${READLINE_LINE:0:READLINE_POINT}" after="${READLINE_LINE:READLINE_POINT}"
    local current="" directive="" candidate common
    local -a words=() candidates=()
    # read without -r keeps a backslash-quoted space inside its word
    read -a words <<< "$before"
    if [ -n "$before" ] && [[ "$before" != *" " ]]
    then
        current="${words[${#words[@]}-1]}"
        unset 'words[${#words[@]}-1]'
    fi
    if [ "${words[0]}" != "playground" ]
    then
        return
    fi
    while IFS= read -r candidate
    do
        if [[ "$candidate" == :options=* ]]
        then
            directive="${candidate#:options=}"
        elif [[ "$candidate" == *"@"* ]]
        then
            # the fzf pickers of the dynamic completions return "<query>@<value> - <description>"
            # (e.g. "8.3@8.3.2 - already installed 💻"): keep the value only
            candidate="${candidate#*@}"
            candidates+=("$(printf '%q' "${candidate%% *}")")
        elif [ -n "$candidate" ]
        then
            candidates+=("$candidate")
        fi
    done < <("$root_folder/scripts/cli/playground" __complete "${words[@]:1}" "$current" 2> /dev/null)
    # file names, as read -e alone: when the CLI asks for them, or has nothing for a path
    if [[ ",$directive," == *",files,"* ]] || [[ ",$directive," == *",directories,"* ]] || { [ ${#candidates[@]} -eq 0 ] && [[ "$current" == */* || "$current" == ~* ]]; }
    then
        local compgen_option="-f"
        [[ ",$directive," == *",directories,"* ]] && compgen_option="-d"
        while IFS= read -r candidate
        do
            [ -d "$candidate" ] && candidate+="/"
            candidates+=("$(printf '%q' "$candidate")")
        done < <(compgen $compgen_option -- "$current")
    fi
    if [ ${#candidates[@]} -eq 0 ]
    then
        return
    fi
    if [ ${#candidates[@]} -eq 1 ]
    then
        common="${candidates[0]}"
        if [[ "$common" != */ ]] && [[ ",$directive," != *",no-space,"* ]]
        then
            common+=" "
        fi
    else
        common="${candidates[0]}"
        for candidate in "${candidates[@]:1}"
        do
            while [[ "$candidate" != "$common"* ]]
            do
                common="${common%?}"
            done
        done
        if [ ${#common} -le ${#current} ]
        then
            # nothing more to complete: show the choices, readline then redraws the line
            printf '%s\n' "${candidates[@]}" | column
            return
        fi
    fi
    READLINE_LINE="${before:0:${#before}-${#current}}$common$after"
    READLINE_POINT=$(( ${#before} - ${#current} + ${#common} ))
}
bind -x '"\t": history_complete' 2> /dev/null

# Prompt the user to edit the res variable
read -e -p "" -i "$res" edited_res

# Use the edited value if it is not empty
if [[ -n "$edited_res" ]]
then
  res="$edited_res"
fi

res=$(history_unmask_creds "$res") || exit 1
eval "$res"
