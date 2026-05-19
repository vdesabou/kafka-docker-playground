"""
CFK Bundle Analyzer — Recommendations layer
Maps detected issue categories to concrete CFK remediation steps.
"""

from typing import Dict, List


RECOMMENDATIONS: Dict[str, Dict[str, object]] = {
    "Pod Failures": {
        "summary": "Pod is crashing or restarting repeatedly.",
        "steps": [
            "kubectl -n <ns> describe pod <pod>  — read Events + last-state termination reason.",
            "kubectl -n <ns> logs <pod> --previous  — capture stack trace from the crashed container.",
            "Check the CR (Kafka/Connect/SchemaRegistry/etc.) for invalid spec.image or spec.configOverrides.",
            "Confirm dependencies (Zookeeper/KRaft controller, MDS, SR) are Ready before this component.",
            "If JVM crash: collect heap dump and JVM logs; raise heap (spec.podTemplate.resources) if OOM.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-troubleshooting.html",
    },
    "Resource Issues": {
        "summary": "Pod was OOMKilled or evicted due to insufficient memory/CPU.",
        "steps": [
            "Inspect spec.podTemplate.resources.{requests,limits} on the affected CR.",
            "For Kafka brokers: raise heap via KAFKA_HEAP_OPTS or spec.configOverrides.jvm — typical broker heap 4–8 GiB.",
            "Confirm node has capacity: kubectl describe node <node> | grep -A5 Allocated.",
            "Add a PodDisruptionBudget if eviction is the failure mode.",
            "Profile usage: kubectl top pods -n <ns> over time before changing limits.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-resource-requirements.html",
    },
    "Image Issues": {
        "summary": "Kubernetes cannot pull the container image.",
        "steps": [
            "kubectl -n <ns> describe pod <pod> | grep -A5 'Failed to pull'  — read exact registry error.",
            "Verify spec.image.application / spec.image.init tags exist in your registry.",
            "Check imagePullSecrets is set on the CR (spec.image.pullSecretRef) for private registries.",
            "Test pull from a worker node: docker pull <image> (or crictl pull) to rule out network/registry auth.",
            "If air-gapped: confirm images mirrored and the registry hostname resolves from cluster DNS.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-network.html",
    },
    "Certificate/TLS Issues": {
        "summary": "TLS handshake failed or certificate could not be verified.",
        "steps": [
            "openssl x509 -in <cert> -noout -dates -subject -issuer  — check expiry and CN.",
            "Confirm SANs cover all DNS names (bootstrap + per-pod) the clients use.",
            "Verify the CA bundle on the client matches the issuing CA of the server cert.",
            "Check the CR's spec.tls.secretRef secret exists and contains tls.crt/tls.key/ca.crt.",
            "If using cert-manager: kubectl describe certificate <name> -n <ns> and inspect ClusterIssuer state.",
            "Restart the component CR after rotating the secret — CFK only re-reads on rolling restart.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-network-encryption.html",
    },
    "Authentication Issues": {
        "summary": "SASL/OAuth/Basic auth is being rejected.",
        "steps": [
            "Inspect spec.authentication.* on the CR — type, jaasConfig, secretRef.",
            "Verify the credential secret exists and keys match (plain.txt / digest.txt for SASL).",
            "For MDS-integrated components: check spec.dependencies.mds.tokenKeyPair and bearer secret.",
            "Tail the component log for 'Authentication failed' and look at the SASL mechanism mismatch.",
            "Confirm clock skew between client and broker is < 5 minutes (Kerberos/OAuth are time-sensitive).",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-authenticate.html",
    },
    "Network Issues": {
        "summary": "Connection refused, timeout, or DNS resolution failure between components.",
        "steps": [
            "Confirm Services exist: kubectl -n <ns> get svc — bootstrap and per-pod headless services.",
            "From a debug pod, nslookup <component>.<ns>.svc.cluster.local and telnet <host> <port>.",
            "Check NetworkPolicies: kubectl -n <ns> get networkpolicy — overly strict policies block intra-cluster traffic.",
            "For external listeners: verify spec.listeners.external.* and the LB/Ingress is provisioned.",
            "Check kube-dns/CoreDNS health if 'no such host' errors are widespread.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-network.html",
    },
    "Scheduling Issues": {
        "summary": "Pod cannot be scheduled onto any node.",
        "steps": [
            "kubectl -n <ns> describe pod <pod> | grep -A10 Events  — read FailedScheduling reason.",
            "If 'Insufficient cpu/memory': scale the node pool or lower spec.podTemplate.resources.requests.",
            "If 'node(s) didn't match Pod's node affinity': review spec.podTemplate.affinity / nodeSelector.",
            "Check taints: kubectl get nodes -o json | jq '.items[].spec.taints' — add matching tolerations.",
            "For StatefulSets that need same-zone PV: confirm storageClass volumeBindingMode is WaitForFirstConsumer.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-scheduling.html",
    },
    "RBAC Issues": {
        "summary": "Kubernetes RBAC is denying an action.",
        "steps": [
            "Identify the failing principal: 'User <x> cannot <verb> <resource>' in the error.",
            "kubectl get clusterrole,clusterrolebinding,role,rolebinding -A | grep <serviceaccount>.",
            "Check the operator's ServiceAccount has the rights granted by the CFK chart's ClusterRole.",
            "Verify your CR's spec.podTemplate.serviceAccountName points to an SA that exists in the namespace.",
            "Reinstall the CFK Helm chart with --set namespaced=true|false matching your topology.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-rbac-kubernetes.html",
    },
    "MDS/RBAC Issues": {
        "summary": "Confluent MDS/RBAC token issuance or validation failed.",
        "steps": [
            "Confirm MDS pod is Ready: kubectl -n <ns> get pods -l app=kafka and check Kafka spec.services.mds.",
            "Verify spec.dependencies.mds.endpoint URL is reachable from the dependent component.",
            "Inspect the MDS public-key secret (tokenKeyPair) — the same key must be on issuer and verifier sides.",
            "Check bearer token secret keys (mdsPublicKey, mdsTokenKeyPair) are not swapped.",
            "Tail Kafka logs for 'TokenBasedSecurityStore' and rotate the token-signing key if compromised.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-rbac.html",
    },
    "License Issues": {
        "summary": "Confluent Enterprise license is expired or invalid.",
        "steps": [
            "kubectl -n <ns> get secret <license-secret> -o jsonpath='{.data.license}' | base64 -d  — inspect.",
            "Update spec.license.secretRef on each Confluent CR (Kafka, Connect, SR, KsqlDB, C3, Operator).",
            "Apply the new secret, then trigger a rolling restart so brokers reload the license.",
            "License JWT is RS256-signed; confirm clock skew on nodes is small or validation will fail.",
            "Engage Confluent support if you need a renewed key — do not patch JARs.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-license.html",
    },
    "Volume Issues": {
        "summary": "PersistentVolume mount failed or PVC is stuck Pending.",
        "steps": [
            "kubectl -n <ns> get pvc  — check STATUS, STORAGECLASS, CAPACITY.",
            "kubectl -n <ns> describe pvc <name>  — read provisioning Events.",
            "Verify the StorageClass exists and the CSI driver pods (e.g. ebs-csi-controller) are Ready.",
            "For zone-pinned volumes: confirm the pod is scheduled to the same zone as the PV.",
            "If a PVC is stuck Terminating: check for finalizers and that no pod still mounts it.",
        ],
        "docs": "https://docs.confluent.io/operator/current/co-storage.html",
    },
    "Init Container Issues": {
        "summary": "An init container failed before the main container could start.",
        "steps": [
            "kubectl -n <ns> logs <pod> -c <init-container-name>  — read the failure.",
            "CFK init containers commonly: render configs, wait for dependencies, install custom JARs.",
            "If 'wait-for-mds' fails: confirm MDS is reachable and the bearer token secret is correct.",
            "If 'config-init-files' fails: validate spec.configOverrides syntax and any sourceRef secrets exist.",
            "For custom-image init: rebuild the image and bump spec.image.init tag.",
        ],
    },
    "Health Check Issues": {
        "summary": "Liveness or readiness probe is failing.",
        "steps": [
            "Identify which probe is failing in 'kubectl describe pod' — liveness restarts the container, readiness pulls it out of the Service.",
            "For Kafka: readiness uses a TCP check on the inter-broker listener — verify the port is listening.",
            "Tune spec.podTemplate.probe.{liveness,readiness}.{initialDelaySeconds,timeoutSeconds} for slow starts.",
            "If a JVM is paused in long GC, readiness flaps — investigate GC (use 'playground debug gc-analyze').",
            "Confirm probe HTTP path/port matches the listener configured on the CR.",
        ],
    },
    "Kubernetes Events": {
        "summary": "Warning/Error events emitted by the kubelet, scheduler, or operator.",
        "steps": [
            "Sort by lastTimestamp: kubectl -n <ns> get events --sort-by=.lastTimestamp.",
            "Group by reason: kubectl get events -A -o json | jq -r '.items[].reason' | sort | uniq -c | sort -rn.",
            "Correlate event timestamps with pod restart timestamps and operator-reconcile logs.",
        ],
    },
    "Kafka Issues": {
        "summary": "Kafka broker reported an exception.",
        "steps": [
            "Identify broker.id from the log; cross-reference with kubectl get pods -l type=kafka.",
            "Check ISR state: kafka-topics --describe --under-replicated-partitions --bootstrap-server …",
            "If 'NotLeaderForPartitionException': transient during leader election, usually self-heals.",
            "If 'CorruptRecordException': isolate the affected partition log segment; consider unclean.leader.election or restore.",
            "Tune spec.configOverrides.server (e.g. log.retention.*, num.network.threads) if the error is config-driven.",
        ],
    },
    "Schema Registry Issues": {
        "summary": "Schema Registry rejected a request or could not find a subject/schema.",
        "steps": [
            "Confirm the _schemas internal topic exists and is healthy (single leader, ISR=replicas).",
            "Check spec.dependencies.kafka points to the right bootstrap and that auth credentials match.",
            "For 'subject not found': verify the producer is registering with the same subject name (TopicNameStrategy vs RecordNameStrategy).",
            "For 'incompatible schema': review compatibility level (BACKWARD/FORWARD/FULL) on the subject.",
        ],
    },
    "Connect Issues": {
        "summary": "Kafka Connect task or connector failed.",
        "steps": [
            "GET /connectors/<name>/status  — read task trace for the root cause.",
            "Check spec.build.plugins or the custom connector image — version mismatches are the common cause.",
            "For credential errors: inspect the connector config secret and confirm the principal has ACLs on source/target topics.",
            "Restart failed task: POST /connectors/<name>/tasks/<id>/restart (or rolling-restart the Connect cluster CR).",
        ],
    },
    "Control Center Issues": {
        "summary": "Confluent Control Center failed to start or render a view.",
        "steps": [
            "Check C3 dependencies in the CR: Kafka, SR, ksqlDB, MDS — all must be reachable.",
            "C3 stores state in internal _confluent-* topics — verify they exist and are not under-replicated.",
            "For 500s: tail control-center pod logs and look for the failing downstream component.",
        ],
    },
    "REST Proxy Issues": {
        "summary": "Kafka REST Proxy failed.",
        "steps": [
            "Tail kafka-rest pod logs; confirm spec.dependencies.kafka credentials are valid.",
            "For 401/403: the principal needs ACLs on the topics it is proxying.",
        ],
    },
    "KsqlDB Issues": {
        "summary": "ksqlDB query, statement, or server failed.",
        "steps": [
            "Check the ksqlDB processing log topic for the failing query's stack trace.",
            "Confirm the command topic (default _confluent-ksql-<service-id>_command_topic) is healthy.",
            "Validate UDF JARs in spec.build.plugins if the failure mentions an unknown function.",
        ],
    },
    "Zookeeper Issues": {
        "summary": "Zookeeper session expired, connection lost, or ensemble unhealthy.",
        "steps": [
            "kubectl -n <ns> exec <zk-pod> -- echo ruok | nc localhost 2181  — expect 'imok'.",
            "Check ZK ensemble forms a quorum: 'echo stat | nc' on each node, look for one Leader + N Followers.",
            "Long GC pauses on brokers cause session timeouts — run 'playground debug gc-analyze' on broker JVM.",
            "If on a KRaft-supported CFK version, plan migration off Zookeeper.",
        ],
    },
    "KRaft Issues": {
        "summary": "KRaft controller quorum or metadata log error.",
        "steps": [
            "Check controller pod logs for 'CurrentEpoch' transitions and election timeouts.",
            "Confirm spec.replicas on the KRaft controller CR is odd (3 or 5) for quorum.",
            "Inspect __cluster_metadata topic — must be intact across all controllers.",
            "If the controller cluster ID drifts, do not delete data — open a Confluent support case.",
        ],
    },
    "Replication Issues": {
        "summary": "Under-replicated partitions or ISR shrink.",
        "steps": [
            "kafka-topics --describe --under-replicated-partitions --bootstrap-server …",
            "Identify the lagging broker; check disk, network, and GC on that broker pod.",
            "If a broker is permanently gone: kafka-reassign-partitions to move replicas to healthy brokers.",
            "Raise replica.fetch.max.bytes / num.replica.fetchers cautiously if fetch throughput is the bottleneck.",
        ],
    },
    "Storage Issues": {
        "summary": "Disk full, PVC pending, or storage subsystem error.",
        "steps": [
            "kubectl -n <ns> exec <pod> -- df -h /var/lib/kafka/data  — capacity check.",
            "If a broker is at >85%: expand the PVC (allowVolumeExpansion on the StorageClass) or shrink retention.",
            "kubectl get events -n <ns> --field-selector reason=FailedAttachVolume.",
            "If PVC stuck Pending: check the StorageClass and CSI driver (PROVISIONER, RECLAIMPOLICY).",
        ],
    },
    "Operator Issues": {
        "summary": "CFK operator failed to reconcile a CR.",
        "steps": [
            "kubectl -n <operator-ns> logs deployment/confluent-operator -f  — look for 'Failed to reconcile <kind>/<name>'.",
            "Validate the CR with: kubectl apply --dry-run=server -f <cr.yaml>.",
            "If a webhook is failing: check the operator's ValidatingWebhookConfiguration and its TLS cert validity.",
            "Restart the operator pod after fixing the CR — it will retry on next reconcile loop.",
        ],
    },
    "Component Status": {
        "summary": "A Confluent component CR has a False condition.",
        "steps": [
            "kubectl -n <ns> get <kind> <name> -o yaml | yq .status.conditions  — read the False condition's message.",
            "Conditions to watch: Ready, RollingUpgrade, ConfigsUpToDate.",
            "If status is stale: confirm the operator is reconciling this CR (operator log + last reconcile timestamp).",
        ],
    },
    "Configuration": {
        "summary": "Suspect configuration on a Confluent CR.",
        "steps": [
            "Compare spec.* against the CFK CR reference for your version.",
            "If replicas=0: someone intentionally scaled it down; otherwise patch back to the expected count.",
            "Run 'kubectl explain <kind>.spec' to confirm fields are valid for the installed CFK version.",
        ],
    },
    "Finalizer Issues": {
        "summary": "Resource deletion is blocked by a finalizer.",
        "steps": [
            "kubectl -n <ns> get <kind> <name> -o yaml | yq .metadata.finalizers.",
            "Confirm the controller that owns the finalizer is running (often the CFK operator itself).",
            "Last resort (data-loss aware): kubectl patch <kind> <name> -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge.",
        ],
    },
    "Reconciliation Blocked": {
        "summary": "block-reconcile annotation is set — operator is intentionally not reconciling.",
        "steps": [
            "Annotation: platform.confluent.io/block-reconcile=true. Someone set this for a reason — investigate before removing.",
            "Remove with: kubectl annotate <kind> <name> platform.confluent.io/block-reconcile-",
        ],
    },
    "Container Status": {
        "summary": "Container is stuck waiting.",
        "steps": [
            "kubectl describe pod — the 'waiting.reason' is the diagnosis (CreateContainerConfigError, CrashLoopBackOff, ImagePullBackOff…).",
            "Apply the remediation for the specific reason in the message.",
        ],
    },
    "Pod Status": {
        "summary": "Pod is in Failed/Unknown phase.",
        "steps": [
            "Capture logs --previous before the pod is GC'd: kubectl logs <pod> --previous --all-containers.",
            "If Unknown: the kubelet on that node is unreachable — check node health.",
        ],
    },
    "Application Errors": {
        "summary": "Java runtime exception in a component.",
        "steps": [
            "java.lang.OutOfMemoryError → raise heap (spec.podTemplate.resources + jvm options) AND capture a heap dump.",
            "java.lang.NullPointerException → version-specific bug; check release notes for the component image tag.",
            "java.io.IOException → almost always network/disk — correlate with Network or Storage issues above.",
        ],
    },
    "Other Critical (Unclassified)": {
        "summary": "A FATAL/SEVERE log line was found that does not match any known CFK pattern.",
        "steps": [
            "Read the issue's context block — FATAL almost always carries enough detail to act on.",
            "Identify the failing component from the file path (e.g. logs/kafka-0.log → broker 0).",
            "Search the exact error string in Confluent docs and KB; FATAL errors usually have a documented cause.",
            "If the same FATAL repeats after restart: capture full pod logs and attach to a Confluent support case.",
            "Until root-caused, do NOT delete the affected pod's PVC — preserve state for the support engineer.",
        ],
    },
    "Other Errors (Unclassified)": {
        "summary": "An ERROR-level log entry was found that does not match a known CFK category.",
        "steps": [
            "Open the context block: 2–5 lines around the error usually identify the subsystem.",
            "Use the file path to identify the component (logs/<component>-<ordinal>.log).",
            "Grep the same log for repeats — one-off ERRORs are often benign, a tight loop is not.",
            "Cross-reference timestamps with Kubernetes Events for that pod to find the upstream cause.",
            "Search the Confluent community + docs for the exact error string; many ERRORs have known KB articles.",
        ],
    },
    "Other Failures (Unclassified)": {
        "summary": "A 'FAILED'/'FAILURE' log line was found that does not match a known pattern.",
        "steps": [
            "Read the context — 'FAILED' is often the symptom, not the cause; the cause is usually 2–10 lines above.",
            "Check whether the failure is retried automatically (look for 'retrying' / 'will retry').",
            "If the operator emitted it: tail confluent-operator logs around the same timestamp.",
        ],
    },
    "Other Exceptions (Unclassified)": {
        "summary": "A Java/Scala stack trace was found that does not map to a known category.",
        "steps": [
            "Read 'Caused by:' at the bottom of the stack — that is the actual root cause.",
            "The first line of the stack tells you which subsystem (Kafka, SR, Connect, …) threw it.",
            "If the trace involves a SerDes / Avro class: suspect schema-evolution or Schema Registry connectivity.",
            "If the trace involves a Selector / Channel / Socket: suspect TLS, network policy, or DNS — see corresponding categories.",
            "Capture the full stack (don't truncate) before opening a support case.",
        ],
    },
    "Other Warnings (Unclassified)": {
        "summary": "A WARN-level log entry was found that does not match a known pattern.",
        "steps": [
            "Warnings are often informational; only act if they correlate in time with an outage or restart.",
            "Repeated warnings about the same partition/connector/principal are worth investigating.",
        ],
    },
}


def for_category(category: str) -> Dict[str, object]:
    """Return recommendation block for a category; falls back to a generic stub."""
    return RECOMMENDATIONS.get(
        category,
        {
            "summary": "No specific remediation mapped for this category.",
            "steps": [
                "Read the issue's context lines for the exact error.",
                "Search Confluent docs and KB for the error string.",
                "If reproducible, open a Confluent support case with this bundle attached.",
            ],
        },
    )


def for_categories(categories: List[str]) -> Dict[str, Dict[str, object]]:
    """Bulk lookup."""
    return {cat: for_category(cat) for cat in categories}
