day="${args[--day]}"
time="${args[--time]}"
older_than="${args[--older-than]}"
max_build_cache="${args[--max-build-cache]}"

parse_schedule_time "$time" || exit 1
if [ "$older_than" -lt 1 ]
then
    logerror "❌ --older-than $older_than must be 1 or more"
    exit 1
fi
days=(sunday monday tuesday wednesday thursday friday saturday)
for i in "${!days[@]}"
do
    [ "${days[$i]}" == "$day" ] && weekday=$i
done

scheduled_job_install docker-cleanup "weekday=$weekday" "$time_hour" "$time_minute" docker-cleanup run --older-than "$older_than" --max-build-cache "$max_build_cache" --scheduled || exit 1
log "🧽 docker cleanup scheduled every $day at $(printf '%02d:%02d' $time_hour $time_minute), older than $older_than days, build cache up to ${max_build_cache}GB ($(scheduled_job_where docker-cleanup))"
log "📄 log: $scheduled_job_log"
log "🔎 what it would remove, as of now:"
playground docker-cleanup run --older-than "$older_than" --max-build-cache "$max_build_cache" --dry-run
log "👉 playground docker-cleanup status   # after the first run"
