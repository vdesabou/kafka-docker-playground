all="${args[--all]}"
keep_latest_patch="${args[--keep-latest-patch]}"
older_than="${args[--older-than]}"
dry_run="${args[--dry-run]}"
yes="${args[--yes]}"
requested=()
if [[ -n "${args[--version]}" ]]
then
    eval "requested=(${args[--version]})"
fi

selection_flags=0
if [[ ${#requested[@]} -gt 0 || -n "$all" || -n "$keep_latest_patch" || -n "$older_than" ]]
then
    selection_flags=1
fi
if [[ $selection_flags -eq 0 && -n "$yes" ]]
then
    logerror "❌ --yes needs a selection: --version, --all, --keep-latest-patch or --older-than"
    exit 1
fi

function remove_cp_images_with_tag () {
    local refs
    refs=$(cp_image_refs_with_tag "$1")
    if [ -z "$refs" ]
    then
        logwarn "no Confluent Platform docker image with tag $1"
        return
    fi
    # no -f: the engine refuses an image still used by a container instead of untagging it
    if ! docker rmi $refs
    then
        logwarn "⚠️ some images of $1 could not be removed (used by a container?)"
    fi
}

function images_disk_usage () {
    docker system df --format '{{.Type}} {{.Size}}' 2>/dev/null | awk '$1 == "Images" {print $2}'
}

function human_size () {
    awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.1fGB", b / 1e9; else if (b >= 1e6) printf "%.0fMB", b / 1e6; else printf "%.0fkB", b / 1e3 }'
}

LATEST_TAG=$(grep "# default tag" "$root_folder/scripts/utils.sh" | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
if [ -z "$LATEST_TAG" ]
then
    logerror "❌ error while getting default TAG "
    exit 1
fi

# TAG of the current run (--tag=x.y.z of the last playground run), kept so that re-run / container recreate do not pull it again
run_tag=$(playground state get run.array_flag_list_base64 2>/dev/null | base64 -d 2>/dev/null | grep -oE -- '--tag=[^" ]+' | head -1 | cut -d "=" -f 2)

# tags of the confluentinc images used by a container, running or stopped (another session, a stopped environment)
in_use_tags=$(docker ps -a --format '{{.Image}}' | awk -F: '{sub(/^docker\.io\//, "", $1)} $1 ~ /^confluentinc\// && NF == 2 {print $2}' | sort -u)

function is_in_use () {
    echo "$in_use_tags" | grep -qxF "$1"
}

# inventory: Confluent Platform versions (tags x.y.z), Control Center next-gen images (cp-enterprise-*, own versioning) left out
declare -A nb_images size_bytes last_used reason selected
inventory=$(docker image ls --format '{{.Repository}} {{.Tag}} {{.Size}} {{.ID}}' | awk '
    function bytes(s,  n, u) { n = s + 0; u = s; sub(/^[0-9.]+/, "", u)
        if (u == "kB" || u == "KB") n *= 1e3; else if (u == "MB") n *= 1e6; else if (u == "GB") n *= 1e9; else if (u == "TB") n *= 1e12
        return n }
    { r = $1; sub(/^docker\.io\//, "", r) }
    r ~ /^confluentinc\// && r !~ /^confluentinc\/cp-enterprise-/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { print $2, bytes($3), $4 }')

image_ids=""
while read -r v b id
do
    [[ -z "$v" ]] && continue
    nb_images[$v]=$(( ${nb_images[$v]:-0} + 1 ))
    size_bytes[$v]=$(awk -v a="${size_bytes[$v]:-0}" -v b="$b" 'BEGIN { printf "%.0f", a + b }')
    image_ids+="$id "
done <<< "$inventory"

# last used: last run with --tag in playground-run-history, or last pull / tag of an image (LastTagTime, not set by podman)
dates=""
if [[ -f "$root_folder/playground-run-history" ]]
then
    dates+=$(awk 'match($0, /--tag[= ][0-9]+\.[0-9]+\.[0-9]+/) { t = substr($0, RSTART + 6, RLENGTH - 6)
        if (match($0, /date=[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print t, substr($0, RSTART + 5, 10) }' "$root_folder/playground-run-history")
    dates+=$'\n'
fi
if [[ -n "$image_ids" ]]
then
    dates+=$(docker image inspect --format '{{range .RepoTags}}{{.}} {{end}}| {{.Metadata.LastTagTime}}' $(echo $image_ids | tr ' ' '\n' | sort -u) 2>/dev/null | awk -F'|' '{
        split($1, refs, " "); d = substr($2, 2, 10)
        if (d !~ /^[0-9][0-9][0-9][0-9]-/ || d ~ /^0001-/) next
        for (i in refs) { n = split(refs[i], p, ":"); print p[n], d } }')
fi
while read -r v d
do
    [[ -z "$v" || -z "${nb_images[$v]}" ]] && continue
    if [[ -z "${last_used[$v]}" || "$d" > "${last_used[$v]}" ]]
    then
        last_used[$v]="$d"
    fi
done <<< "$dates"

all_versions=$(printf '%s\n' "${!nb_images[@]}" | sort -V)
candidates=()
for v in $all_versions
do
    if is_in_use "$v"
    then
        reason[$v]="⏭️ used by a container"
    elif [[ "$v" == "$LATEST_TAG" ]]
    then
        reason[$v]="⏭️ default TAG"
    elif [[ -n "$run_tag" && "$v" == "$run_tag" ]]
    then
        reason[$v]="⏭️ current run TAG"
    else
        candidates+=("$v")
    fi
done

# selection
extra_versions=""
for req in "${requested[@]}"
do
    if [[ -n "$(cp_image_refs_with_tag "$req")" ]]
    then
        # exact version (any tag, even one not listed like 7.9.6-1-ubi8)
        if is_in_use "$req"
        then
            logerror "❌ Confluent Platform $req is used by a container, stop it first (playground stop, or docker ps -a)"
            exit 1
        fi
        if [[ -n "${reason[$req]}" ]]
        then
            logwarn "⚠️ $req is the ${reason[$req]#⏭️ }, removed because asked by name"
        fi
        if [[ -z "${nb_images[$req]}" ]]
        then
            extra_versions+="$req "
            nb_images[$req]=$(cp_image_refs_with_tag "$req" | wc -l | tr -d ' ')
        fi
        selected[$req]=1
    else
        matched=0
        for v in "${candidates[@]}"
        do
            if [[ "$v" == "$req".* ]]
            then
                selected[$v]=1
                matched=1
            fi
        done
        if [[ $matched -eq 0 ]]
        then
            logwarn "⚠️ no Confluent Platform version installed matching $req (protected versions are only removed when named exactly)"
        fi
    fi
done
if [[ ${#requested[@]} -eq 0 && $selection_flags -eq 1 ]]
then
    for v in "${candidates[@]}"
    do
        selected[$v]=1
    done
fi

if [[ -n "$keep_latest_patch" ]]
then
    declare -A latest_patch
    for v in $all_versions
    do
        latest_patch[${v%.*}]="$v"
    done
    for v in "${latest_patch[@]}"
    do
        if [[ -n "${selected[$v]}" ]]
        then
            unset "selected[$v]"
            reason[$v]="⏭️ latest patch of ${v%.*}"
        fi
    done
fi

if [[ -n "$older_than" ]]
then
    cutoff=$(date -u -d "-${older_than} days" +%F 2>/dev/null || date -u -v-"${older_than}"d +%F)
    for v in "${!selected[@]}"
    do
        if [[ -n "${last_used[$v]}" && ! "${last_used[$v]}" < "$cutoff" ]]
        then
            unset "selected[$v]"
            reason[$v]="⏭️ used since $cutoff"
        fi
    done
fi

# no selection flag: CI keeps the old behaviour (all), --dry-run shows the plan of --all
if [[ $selection_flags -eq 0 && ( -n "$GITHUB_RUN_NUMBER" || -n "$dry_run" ) ]]
then
    for v in "${candidates[@]}"
    do
        selected[$v]=1
    done
    selection_flags=1
fi

# table
if [[ -z "$all_versions" && -z "$extra_versions" ]]
then
    log "🧹 no Confluent Platform docker image installed locally"
    exit 0
fi
log "🧹 Confluent Platform versions installed locally (default TAG $LATEST_TAG${run_tag:+, current run TAG $run_tag})"
printf '%-12s %6s %9s  %-10s  %s\n' "VERSION" "IMAGES" "SIZE" "LAST USED" "ACTION"
for v in $all_versions $extra_versions
do
    if [[ -n "${selected[$v]}" ]]
    then
        action="🧹 remove"
    else
        action="${reason[$v]}"
    fi
    size="-"
    if [[ -n "${size_bytes[$v]}" ]]
    then
        size=$(human_size "${size_bytes[$v]}")
    fi
    printf '%-12s %6s %9s  %-10s  %s\n' "$v" "${nb_images[$v]}" "$size" "${last_used[$v]:--}" "$action"
done
echo ""

ordered_selection () {
    for v in $all_versions $extra_versions
    do
        if [[ -n "${selected[$v]}" ]]
        then
            echo "$v"
        fi
    done
}

if [[ $selection_flags -eq 0 ]]
then
    if [[ ${#candidates[@]} -eq 0 ]]
    then
        log "🧹 no Confluent Platform docker image to remove"
        exit 0
    fi
    if [[ -t 0 && -t 1 ]] && command -v fzf > /dev/null 2>&1
    then
        fzf_version=$(get_fzf_version)
        if version_gt $fzf_version "0.38"
        then
            fzf_option_pointer="--pointer=👉"
            fzf_option_rounded="--border=rounded"
        else
            fzf_option_pointer=""
            fzf_option_rounded=""
        fi
        lines=()
        for v in "${candidates[@]}"
        do
            lines+=("$(printf '%-12s %3s images %9s  last used %s' "$v" "${nb_images[$v]}" "$(human_size "${size_bytes[$v]}")" "${last_used[$v]:--}")")
        done
        res=$(printf '%s\n' "${lines[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🧹" --header="select the versions to remove (tab to select more than one, <esc> to cancel)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_pointer)
        if [[ -z "$res" ]]
        then
            log "🧹 nothing selected"
            exit 0
        fi
        for v in $(echo "$res" | awk '{print $1}')
        do
            selected[$v]=1
        done
    else
        # no fzf (or no terminal): ask before every version
        remove_all=0
        before=$(images_disk_usage)
        for v in "${candidates[@]}"
        do
            if [[ $remove_all -eq 0 ]]
            then
                while true
                do
                    # no answer can come (stdin closed: a script, an agent): use a selection flag instead
                    if ! read -r -p "Remove $v ($(human_size "${size_bytes[$v]}"))? [y]es / [n]o, skip it / [a]ll remaining / [q]uit: " choice
                    then
                        logerror "❌ no answer: stdin is closed, answer it in a terminal or use --version, --all, --keep-latest-patch or --older-than (with --yes)"
                        exit 1
                    fi
                    case "$choice" in
                        y|Y ) break;;
                        n|N ) log "⏭️ $v skipped"; continue 2;;
                        a|A ) remove_all=1; break;;
                        q|Q ) break 2;;
                        * ) logwarn "invalid response <$choice>! Please enter y, n, a or q.";;
                    esac
                done
            fi
            log "🧹 removing Confluent Platform docker images: $v"
            remove_cp_images_with_tag "$v"
            selected[$v]=1
        done
        if [[ ${#selected[@]} -gt 0 ]]
        then
            log "✅ removed ${#selected[@]} version(s): images ${before:-?} → $(images_disk_usage)"
        fi
        exit 0
    fi
fi

to_remove=$(ordered_selection)
if [[ -z "$to_remove" ]]
then
    log "🧹 no Confluent Platform docker image to remove"
    exit 0
fi
total=0
for v in $to_remove
do
    total=$(awk -v a="$total" -v b="${size_bytes[$v]:-0}" 'BEGIN { printf "%.0f", a + b }')
done
log "🧹 $(echo "$to_remove" | wc -l | tr -d ' ') version(s) to remove, up to $(human_size "$total") (an upper bound: a layer shared by several images is counted in each): $(echo $to_remove)"

if [[ -n "$dry_run" ]]
then
    for v in $to_remove
    do
        log "🔎 dry-run, would run: docker rmi $(cp_image_refs_with_tag "$v" | tr '\n' ' ')"
    done
    exit 0
fi

if [[ -z "$yes" && -z "$res" ]]
then
    check_if_continue
fi

before=$(images_disk_usage)
for v in $to_remove
do
    log "🧹 removing Confluent Platform docker images: $v"
    remove_cp_images_with_tag "$v"
done
log "✅ removed $(echo "$to_remove" | wc -l | tr -d ' ') version(s): images ${before:-?} → $(images_disk_usage)"
dangling=$(docker image ls -q -f dangling=true 2>/dev/null | wc -l | tr -d ' ')
if [[ "$dangling" -gt 0 ]]
then
    log "🎓 $dangling dangling image(s) left on disk (not all from Confluent Platform): 'docker image prune' removes them"
fi
