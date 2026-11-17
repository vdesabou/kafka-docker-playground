to="${args[--to]}"
no_block_reconcile="${args[--no-block-reconcile]}"
skip_crds="${args[--skip-crds]}"
keep_init_images="${args[--keep-init-images]}"
timeout="${args[--timeout]}"

# The CFK upgrade procedure (docs.confluent.io/operator/current/co-upgrade-cfk.html): reconciliation blocked on every
# custom resource, CRDs, helm upgrade, init container images staged, then reconciliation enabled again one component at
# a time: each component rolls once, with the new operator and the new init container together
chart_version=$(get_cfk_helm_chart_version "$to") || exit 1
current_chart=$(helm -n confluent list --filter '^confluent-operator$' -o json 2>/dev/null | jq -r '.[0].chart // empty')
if [[ -z "$current_chart" ]]
then
    logerror "❌ no helm release confluent-operator in namespace confluent"
    exit 1
fi
log "☸️ CFK operator: $current_chart → confluent-for-kubernetes-$chart_version (CFK $to)"
if ! helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "confluentinc"
then
    helm repo add confluentinc https://packages.confluent.io/helm > /dev/null
fi
helm repo update confluentinc > /dev/null

day1_crs=$(cfk_cr_list)
# every custom resource of the namespace, day-1 and day-2 (KafkaTopic, Connector, ConfluentRolebinding...)
all_crs=$(kubectl api-resources --api-group=platform.confluent.io --namespaced -o name 2>/dev/null | while read -r kind
do
    kubectl -n confluent get "$kind" -o name 2>/dev/null
done)

if [[ -z "$no_block_reconcile" ]]
then
    log "⏸️ Step 1: block reconciliation on the $(echo "$all_crs" | sed '/^$/d' | wc -l | tr -d ' ') custom resources (platform.confluent.io/block-reconcile=true): the operator upgrade does not roll anything"
    for cr in $all_crs
    do
        kubectl -n confluent annotate "$cr" platform.confluent.io/block-reconcile=true --overwrite > /dev/null
    done
else
    logwarn "⚠️ reconciliation not blocked (--no-block-reconcile): the new operator reconciles every custom resource as soon as it starts, all components roll at the same time"
fi

if version_gt "$to" "3.3.99"
then
    log "📜 Step 2: CFK $to manages its own CRDs (helm value manageCRDs, true by default): nothing to apply"
elif [[ -n "$skip_crds" ]]
then
    logwarn "⚠️ CRDs not applied (--skip-crds): helm never upgrades the CRDs of a chart, the operator of CFK $to runs with the CRDs of the old version"
else
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    helm pull confluentinc/confluent-for-kubernetes --version "$chart_version" --untar --untardir "$tmp_dir"
    log "📜 Step 2: apply the CRDs of the new chart (helm never upgrades them)"
    kubectl apply --server-side --force-conflicts -f "$tmp_dir/confluent-for-kubernetes/crds/" | sed 's/^/   /'
fi

declare -A generation_before
for cr in $day1_crs
do
    generation_before[$cr]=$(cfk_statefulset_generation "${cr#*/}")
done
since=$(date +%s)
log "⬆️ Step 3: helm upgrade confluent-operator --version $chart_version"
# --reset-then-reuse-values: the defaults of the new chart (image.tag of the new operator) plus the values given at
# install. --reuse-values would keep the computed values of the old release, image.tag included: the new chart with the
# old operator image
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --version "$chart_version" --namespace confluent --reset-then-reuse-values > /dev/null
kubectl -n confluent rollout status deployment/confluent-operator --timeout=300s
operator_image=$(kubectl -n confluent get deployment confluent-operator -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$operator_image" != *":$chart_version" ]]
then
    logerror "❌ the operator runs $operator_image, not the image of chart $chart_version (an image.tag in the values of the release?)"
    exit 1
fi
log "✅ CFK operator $operator_image"

function stage_init_images () {
    # $1: 1 to wait for the roll of each custom resource
    local cr init new_init
    for cr in $day1_crs
    do
        init=$(kubectl -n confluent get "$cr" -o jsonpath='{.spec.image.init}')
        new_init="${init%:*}:${to}"
        if [[ -z "$init" ]] || [[ "$init" == "$new_init" ]]
        then
            continue
        fi
        log "🧷 $cr: init container $init → $new_init"
        if [[ "$1" == "1" ]]
        then
            cfk_patch_and_wait "$cr" "{\"spec\": {\"image\": {\"init\": \"$new_init\"}}}" merge "$timeout" || exit 1
        else
            kubectl -n confluent patch "$cr" --type merge -p "{\"spec\": {\"image\": {\"init\": \"$new_init\"}}}" > /dev/null
        fi
    done
}

rc=0
if [[ -z "$no_block_reconcile" ]]
then
    if [[ -z "$keep_init_images" ]]
    then
        log "🧷 Step 4: stage the init container images (reconciliation still blocked: no roll yet)"
        stage_init_images 0
    fi
    log "▶️ Step 5: enable reconciliation again, one component at a time: each one rolls once (new operator and new init container)"
    for cr in $day1_crs
    do
        cr_since=$(date +%s)
        cr_generation=$(cfk_statefulset_generation "${cr#*/}")
        kubectl -n confluent annotate "$cr" platform.confluent.io/block-reconcile- > /dev/null
        if ! cfk_wait_rollout "$cr" "$cr_generation" "$timeout" "$cr_since"
        then
            rc=1
            break
        fi
    done
    for cr in $all_crs
    do
        kubectl -n confluent annotate "$cr" platform.confluent.io/block-reconcile- > /dev/null 2>&1 || true
    done
else
    log "⏳ the new operator reconciles every component at once"
    for cr in $day1_crs
    do
        cfk_wait_rollout "$cr" "${generation_before[$cr]}" "$timeout" "$since" || rc=1
    done
    if [[ $rc -eq 0 ]] && [[ -z "$keep_init_images" ]]
    then
        log "🧷 the init container images, changed after the operator upgrade: a second roll of every component"
        stage_init_images 1
    fi
fi
log "📦 Versions after the operator upgrade"
cfk_print_versions
exit $rc
