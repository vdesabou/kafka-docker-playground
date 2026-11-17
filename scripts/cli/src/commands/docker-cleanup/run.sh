older_than="${args[--older-than]}"
max_build_cache="${args[--max-build-cache]}"
dry_run="${args[--dry-run]}"
scheduled="${args[--scheduled]}"

if [ "$older_than" -lt 1 ]
then
    logerror "❌ --older-than $older_than must be 1 or more"
    exit 1
fi
if [ "$max_build_cache" -lt 0 ]
then
    logerror "❌ --max-build-cache $max_build_cache must be 0 or more"
    exit 1
fi

if [[ -n "$scheduled" ]]
then
    log "🧽 docker cleanup of $(date '+%Y-%m-%d %H:%M'), older than $older_than days, build cache up to ${max_build_cache}GB"
fi
if ! docker info > /dev/null 2>&1
then
    # nothing to free, and nobody to start it at that time: the next run will do it
    log "💤 the container engine is not running: skipped"
    exit 0
fi
if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run: listing what would be removed, nothing is removed"
fi

# size of the line $1 of docker system df (Images, Build Cache), as docker prints it (12.3GB)
docker_df_size () {
    docker system df --format '{{.Type}}\t{{.Size}}' 2> /dev/null | awk -F'\t' -v t="$1" '$1 == t {print $2}'
}
# 12.3GB, 512MB, 0B → bytes, and back (decimal units, as docker and podman print them)
size_to_bytes () {
    awk -v s="$1" 'BEGIN { n = s + 0; u = s; sub(/^[0-9.]+/, "", u)
        if (u == "kB" || u == "KB") n *= 1e3; else if (u == "MB") n *= 1e6; else if (u == "GB") n *= 1e9; else if (u == "TB") n *= 1e12
        printf "%.0f", n }'
}
bytes_to_size () {
    awk -v b="$1" 'BEGIN { if (b >= 1e12) printf "%.2fTB", b / 1e12; else if (b >= 1e9) printf "%.2fGB", b / 1e9; else if (b >= 1e6) printf "%.0fMB", b / 1e6; else if (b >= 1e3) printf "%.0fkB", b / 1e3; else printf "%.0fB", b }'
}
podman=""
if container_engine_is_podman
then
    podman=1
fi
images_before=$(docker_df_size Images)
cache_before=$(docker_df_size "Build Cache")

log "🧹 Confluent Platform versions not used for $older_than days"
cp_args=(--older-than "$older_than" --yes)
if [[ -n "$dry_run" ]]
then
    cp_args+=(--dry-run)
fi
playground remove-cp-docker-images "${cp_args[@]}" || logwarn "⚠️ playground remove-cp-docker-images failed, going on with the dangling images and the build cache"

nb_dangling=$(docker images --filter dangling=true --quiet 2> /dev/null | sort -u | wc -l | tr -d ' ')
if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run, would run: docker image prune --force   # $nb_dangling dangling image(s), the ones used by a container are kept"
else
    log "🗑️ removing the dangling images ($nb_dangling, the ones used by a container are kept)"
    # its "Total reclaimed space" is not used: podman adds up the full size of each image, shared layers included
    docker image prune --force > /dev/null 2>&1 || logwarn "⚠️ docker image prune failed"
fi

# docker 28 renamed --keep-storage to --max-used-space
cap_flag="--keep-storage"
if [[ -z "$podman" ]] && docker builder prune --help 2> /dev/null | grep -q -- "--max-used-space"
then
    cap_flag="--max-used-space"
fi
if [[ -n "$podman" ]]
then
    # podman builds keep their layers as images (pruned above), there is no BuildKit cache to cap
    log "🧱 podman: no build cache to prune, skipped"
elif [[ -n "$dry_run" ]]
then
    log "🔎 dry-run, would run: docker builder prune --force $cap_flag ${max_build_cache}GB   # build cache now: ${cache_before:-?}"
else
    log "🧱 removing the build cache above ${max_build_cache}GB, least recently used first"
    docker builder prune --force "$cap_flag" "${max_build_cache}GB" > /dev/null 2>&1 || logwarn "⚠️ docker builder prune failed"
fi

if [[ -z "$dry_run" ]]
then
    images_after=$(docker_df_size Images)
    cache_after=$(docker_df_size "Build Cache")
    # what the disk really lost, from docker system df: the old Confluent Platform versions included
    freed="?"
    if [[ -n "$images_before" && -n "$images_after" ]]
    then
        freed_bytes=$(( $(size_to_bytes "$images_before") + $(size_to_bytes "${cache_before:-0B}") - $(size_to_bytes "$images_after") - $(size_to_bytes "${cache_after:-0B}") ))
        # images pulled by another session in the meantime
        [ "$freed_bytes" -lt 0 ] && freed_bytes=0
        freed=$(bytes_to_size "$freed_bytes")
    fi
    summary="freed $freed (images ${images_before:-?} → ${images_after:-?}"
    if [[ -z "$podman" ]]
    then
        summary+=", build cache ${cache_before:-?} → ${cache_after:-?}"
    fi
    summary+=")"
    log "✅ $summary"
    # the layers of the build cache shared with images are freed only with those images, whatever --max-build-cache
    cache_shared=$(docker buildx du 2> /dev/null | awk '/^Shared:/ {print $2}')
    if [ -n "$cache_shared" ]
    then
        log "🎓 $cache_shared of the build cache are layers shared with images: freed with the images only (playground remove-cp-docker-images)"
    fi
    if [[ -n "$scheduled" ]]
    then
        scheduled_job_notify "🧽 kafka-docker-playground docker cleanup" "$summary"
    fi
fi
