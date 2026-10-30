mine="${args[--mine]}"
case_number="${args[--case]}"
status_filter="${args[--status]}"
verdict_filter="${args[--verdict]}"
base_filter="${args[--base]}"
since="${args[--since]}"
grep_filter="${args[--grep]}"
uncommitted="${args[--uncommitted]}"
limit="${args[--limit]}"
json="${args[--json]}"

repro_root="$root_folder/reproduction-models"
if [ ! -d "$repro_root" ]
then
    logerror "❌ folder $repro_root does not exist"
    exit 1
fi
repro_root=$(cd -P "$repro_root" && pwd)

since_days=""
since_date=""
if [ -n "$since" ]
then
    if [[ "$since" =~ ^([0-9]+)d$ ]]
    then
        since_days="${BASH_REMATCH[1]}"
    elif [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
    then
        since_date="$since"
    else
        logerror "❌ --since takes a number of days (90d) or a date (2026-01-31)"
        exit 1
    fi
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

# 1. the header of every model, in one pass (only its first 30 lines are read)
find "$repro_root" -mindepth 2 -maxdepth 2 -type f -name '*-repro-*.sh' -print0 > "$tmp_dir/files"
if [ ! -s "$tmp_dir/files" ]
then
    logwarn "🤷 no reproduction model in $repro_root"
    exit 0
fi
xargs -0 awk '
    function field(line, key) { sub("^# [^ ]+ " key ": ?", "", line); gsub("\t", " ", line); return line }
    FNR == 1 { if (file != "") print_model(); file = FILENAME; date = author = description = expected = actual = jira = status = "" }
    FNR > 30 { nextfile }
    /^# [^ ]+ date: / && date == "" { date = field($0, "date") }
    /^# [^ ]+ author: / && author == "" { author = field($0, "author") }
    /^# [^ ]+ description: / && description == "" { description = field($0, "description") }
    /^# [^ ]+ expected:/ && expected == "" { expected = field($0, "expected") }
    /^# [^ ]+ actual:/ && actual == "" { actual = field($0, "actual") }
    /^# [^ ]+ jira:/ && jira == "" { jira = field($0, "jira") }
    /^# [^ ]+ status:/ && status == "" { status = field($0, "status") }
    function print_model() { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", file, date, author, description, expected, actual, jira, status }
    END { if (file != "") print_model() }' < "$tmp_dir/files" > "$tmp_dir/headers.tsv"

# 2. what is not in the headers: the base example (the symlinks of each folder), the date the model was committed (models
# without a date in their header), the uncommitted models, the last verdict of 'playground repro assert'
for dir in "$repro_root"/*/
do
    target=$(readlink "${dir}README.md" 2>/dev/null || readlink "${dir}stop.sh" 2>/dev/null || true)
    if [[ "$target" == ../../* ]]
    then
        printf '%s\t%s\n' "$(basename "$dir")" "$(dirname "${target#../../}")"
    fi
done > "$tmp_dir/bases.tsv"
: > "$tmp_dir/added.tsv"
: > "$tmp_dir/uncommitted"
if [ -e "$repro_root/.git" ]
then
    # oldest first, so the last line of a file is the commit that added (or renamed) it
    git -C "$repro_root" log --reverse --diff-filter=AR --name-only --format='@%as' -- '*-repro-*.sh' 2>/dev/null \
        | awk '/^@/ { date = substr($0, 2); next } NF { print $0 "\t" date }' > "$tmp_dir/added.tsv"
    git -C "$repro_root" status --porcelain --untracked-files=all 2>/dev/null | awk '{ print $NF }' | grep -- '-repro-.*\.sh$' > "$tmp_dir/uncommitted" || true
fi
: > "$tmp_dir/verdicts.tsv"
if [ -f "$root_folder/playground-repro-verdicts" ]
then
    jq -r '[.script, .verdict, .date[0:10], .cp_version, .connector_version] | @tsv' "$root_folder/playground-repro-verdicts" 2>/dev/null > "$tmp_dir/verdicts.tsv" || true
fi

# 3. one JSON object per model, then the filters
models=$(jq -n -R \
    --arg repro_root "$repro_root" \
    --rawfile headers "$tmp_dir/headers.tsv" \
    --rawfile bases "$tmp_dir/bases.tsv" \
    --rawfile added "$tmp_dir/added.tsv" \
    --rawfile uncommitted "$tmp_dir/uncommitted" \
    --rawfile verdicts "$tmp_dir/verdicts.tsv" '
    def lines($s): $s | split("\n") | map(select(length > 0) | split("\t"));
    def months: {"jan":"01","feb":"02","mar":"03","apr":"04","may":"05","jun":"06","jul":"07","aug":"08","sep":"09","oct":"10","nov":"11","dec":"12"};
    # "Fri Oct 30 09:31:17 CET 2026", "Fri 01 Sep 2023 07:25:14 AM UTC", "Tue Sep 15 2026"
    def header_date: split(" ") as $t
        | ([$t[] | select(test("^[0-9]{4}$"))][0]) as $y
        | ([$t[] | ascii_downcase | .[0:3] | select(months[.] != null)][0]) as $m
        | ([$t[] | select(test("^[0-9]{1,2}$"))][0]) as $d
        | if $y and $m and $d then "\($y)-\(months[$m])-\(if ($d | length) == 1 then "0" + $d else $d end)" else "" end;
    (lines($bases) | map({key: .[0], value: .[1]}) | from_entries) as $bases
    | (lines($added) | map({key: .[0], value: .[1]}) | from_entries) as $added
    | (lines($uncommitted) | map(.[0])) as $uncommitted
    | (lines($verdicts) | map({key: .[0], value: {verdict: .[1], date: .[2], cp_version: .[3], connector_version: (.[4] // "")}}) | from_entries) as $verdicts
    | [lines($headers)[]
        | (.[0] | ltrimstr($repro_root + "/")) as $path
        | ($path | split("/")[1] | capture("-repro-(?<d>.*)\\.sh$").d // "") as $name
        | ((.[3] // "") | if . == "" then ($name | gsub("-"; " ")) else . end) as $description
        | {
            path: $path,
            script: .[0],
            created: ((.[1] // "") | header_date | if . == "" then ($added[$path] // "") else . end),
            author: (.[2] // ""),
            description: $description,
            case: (($description | capture("^(?<c>[0-9]{6})")?.c) // ""),
            expected: (.[4] // ""),
            actual: (.[5] // ""),
            jira: (.[6] // ""),
            status: (.[7] // ""),
            base_example: ($bases[$path | split("/")[0]] // ""),
            committed: (($uncommitted | index($path)) == null),
            last_verdict: ($verdicts[.[0]] // null)
          }]')

me=$(whoami)
filtered=$(echo "$models" | jq \
    --arg me "$me" --arg mine "$mine" --arg case "$case_number" --arg status "$status_filter" --arg verdict "$verdict_filter" \
    --arg base "$base_filter" --arg since_days "$since_days" --arg since_date "$since_date" --arg grep "$grep_filter" \
    --arg uncommitted "$uncommitted" '
    (if $since_days != "" then (now - ($since_days | tonumber) * 86400 | strftime("%Y-%m-%d")) else $since_date end) as $since
    | map(select(
        ($mine == "" or .author == $me)
        and ($case == "" or .case == $case or (.path | contains($case)))
        and ($status == "" or (.status | ascii_downcase | contains($status | ascii_downcase)))
        and ($verdict == "" or ($verdict == "none" and .last_verdict == null) or (.last_verdict != null and (.last_verdict.verdict | gsub(" "; "-")) == $verdict))
        and ($base == "" or (.base_example | contains($base)))
        and ($since == "" or (.created != "" and .created >= $since))
        and ($grep == "" or ([.description, .expected, .actual, .path, .jira] | join(" ") | test($grep; "i")))
        and ($uncommitted == "" or (.committed | not))))
    | sort_by(.created, .path) | reverse')

total=$(echo "$models" | jq 'length')
count=$(echo "$filtered" | jq 'length')
if [ -n "$limit" ] && [ "$limit" != "0" ]
then
    shown=$(echo "$filtered" | jq --argjson limit "$limit" '.[:$limit]')
else
    shown="$filtered"
fi

if [[ -n "$json" ]]
then
    echo "$shown"
    exit 0
fi

if [ "$count" -eq 0 ]
then
    log "🤷 no reproduction model matches, out of $total"
    exit 0
fi
log "👷 $count reproduction model(s) out of $total, newest first$( [ "$count" -gt "$(echo "$shown" | jq 'length')" ] && echo ", the first $limit (--limit 0 for all)")"
# printf pads bytes, and an emoji is 4 bytes for 2 columns: 2 more for each label
printf '   %-12s  %-8s  %-18s  %-18s  %s\n' "📅 created" "🔮 case" "🩹 status" "🧪 last verdict" "💡 description"
echo "$shown" | jq -r '.[] | [
        (if .created == "" then "?" else .created end),
        (if .case == "" then "-" else .case end),
        (if .status == "" then "-" else .status end),
        (if .last_verdict == null then "-" elif .last_verdict.verdict == "reproduced" then "🐞 \(.last_verdict.date)" else "✅ \(.last_verdict.date)" end),
        (.description + (if .committed then "" else " ✏️" end)),
        .path] | @tsv' \
    | while IFS=$'\t' read -r created case status verdict description path
    do
        verdict_width=16
        if [ "$verdict" != "-" ]
        then
            verdict_width=18
        fi
        printf "   %-10s  %-6s  %-16.16s  %-${verdict_width}s  %.70s\n" "$created" "$case" "$status" "$verdict" "$description"
        printf '   %-10s  ↳ %s\n' "" "$path"
    done
log "💡 details: playground repro status -f $repro_root/<path> | run: playground run -f $repro_root/<path>"
