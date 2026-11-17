to="${args[--to]}"
timeout="${args[--timeout]}"

log "⬆️ Upgrade of every custom resource to CP $to, one at a time, controllers first"
for cr in $(cfk_cr_list)
do
    image=$(kubectl -n confluent get "$cr" -o jsonpath='{.spec.image.application}')
    new_image="${image%:*}:${to}"
    if [[ "$image" == "$new_image" ]]
    then
        log "ℹ️ $cr already runs $image"
        continue
    fi
    log "⬆️ $cr: $image → $new_image"
    if ! cfk_patch_and_wait "$cr" "{\"spec\": {\"image\": {\"application\": \"$new_image\"}}}" merge "$timeout"
    then
        logerror "❌ upgrade stopped at $cr, the next custom resources are not changed"
        exit 1
    fi
done
log "📦 Versions after the upgrade"
cfk_print_versions
if kubectl -n confluent get kraftcontroller > /dev/null 2>&1 && [[ -n "$(kubectl -n confluent get kraftcontroller -o name 2>/dev/null)" ]]
then
    log "🏷️ Feature levels (kafka-features describe): metadata.version stays at the old version until 'kafka-features upgrade'"
    kubectl -n confluent exec kafka-0 -c kafka -- kafka-features --bootstrap-server kafka:9071 describe 2>/dev/null | grep -E "metadata.version|kraft.version" | sed 's/^/   /' || logwarn "⚠️ kafka-features describe failed (secured listener?)"
fi
