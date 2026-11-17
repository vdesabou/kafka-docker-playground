# 🔁 Day-2 operations: upgrades and changes on a running cluster (cp-ansible and CFK)

Deploying Confluent Platform is day 1. Everything after it is **day 2**: upgrade Confluent Platform, upgrade the tool
that deploys it, enable security, add brokers, change the KRaft quorum, change a property. This is where customers
open cases ("our producers failed during the upgrade", "every pod restarted twice", "the brokers still run the old
value"), and where adopting cp-ansible or Confluent for Kubernetes (CFK) is won or lost.

The playground replays these changes **on a running cluster, with a workload running through them**, the way the
cp-ansible and CFK procedures describe them, and shows at each step:

- 👀 what the clients see: a producer with **no retries**, so every disruption is a send error, the longest time
  without an ack, the send errors per minute and exception
- 💥 what the **classic mistake** looks like next to the right procedure, measured on the same cluster
- 🔧 **every low-level command** that is run (`kubectl`, `helm`, `ansible-playbook`, `docker exec`, `kafka-features`,
  `yq`…), printed before it runs, so that you can follow what is done and replay it by hand on a customer setup
- ✅ at the end, that **no record was lost**: every acked record is in the topic, and the sink connector got them all

| Platform | Example | Change | The classic mistake it shows |
| --- | --- | --- | --- |
| 🅰️ cp-ansible | [`rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/rolling-upgrade.sh) | CP 8.3.2 → the default CP version, 3 brokers | the default `deployment_strategy` of cp-ansible (`parallel`) restarts every broker at once; the feature level is not finalized |
| 🅰️ cp-ansible | [`enable-sasl-ssl.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-sasl-ssl.sh) | PLAINTEXT → SASL_SSL without downtime, in 3 steps | a client left on PLAINTEXT: `Bootstrap broker … disconnected` in a loop, or `OutOfMemoryError` (KAFKA-4090) |
| 🅰️ cp-ansible | [`scale-out-brokers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/scale-out-brokers.sh) | 1 → 3 brokers | the new brokers hold nothing until the topics are reassigned; the internal topics keep one replica |
| 🅰️ cp-ansible | [`static-to-dynamic-quorum.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/static-to-dynamic-quorum.sh) | static KRaft quorum → dynamic, then 2 controllers added | `kraft_dynamic_quorum_enabled` and the normal playbook on a static cluster: cp-ansible refuses it |
| 🅰️ cp-ansible | [`enable-rbac.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-rbac.sh) | SASL_SSL → RBAC (MDS, LDAP) | the INTERNAL listener becomes OAUTHBEARER only; an application without a role binding is denied at once |
| ☸️ CFK | [`cfk-rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-rolling-upgrade.sh) | CP 8.3.2 → the default CP version, 3 controllers, 3 brokers | a JSON merge patch of `configOverrides` replaces the whole list; the feature level is not finalized; a change applied right after a roll that the brokers don't get |
| ☸️ CFK | [`cfk-operator-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-operator-upgrade.sh) | CFK 3.3.0 → 3.3.1, then → 3.4.0 | `helm upgrade` without blocking reconciliation: every pod restarts twice, controllers and brokers at the same time |

```bash
playground run -f other/cp-ansible-day2/rolling-upgrade.sh                       # 🅰️ each one starts its own environment
playground run -f other/cfk-day2/cfk-operator-upgrade.sh --environment cfk       # ☸️ needs k3d, kubectl, helm
```

Each example takes 15 to 30 minutes, and runs every night in CI (`other/cp-ansible-day2` in the plaintext job,
`other/cfk-day2` in the cfk job). The same `playground ansible` and `playground cfk` commands work by hand on any
ansible or cfk environment, including a customer's inventory (`--ansible-inventory`).

---

## 1. The workload, and how to read the output

Both families use the same workload, so their numbers compare:

| Piece | cp-ansible | CFK |
| --- | --- | --- |
| producer | `kafka-verifiable-producer` on the connect host, 20 records/s, `acks=all`, no retries, one JSON line per ack and per error | the same, in its own pod `day2-client` (not managed by CFK: the CFK pods are rolled by the changes) |
| topic | `day2`, 3 partitions, replication factor 3, `min.insync.replicas=2` | the same |
| sink | FileStream sink connector, writing the topic to a file | FileStream sink connector, checked by the lag of its consumer group |
| restarts | journald of each host (`Stopping confluent-server`) | pod start times, and the `Killing` events of Kubernetes (every stop of every pod) |
| end check | acked = records in the topic = lines of the sink file | acked = records in the topic, sink lag 0 |

What the lines mean:

| Line | Meaning |
| --- | --- |
| `🔧 kubectl -n confluent patch kafka/kafka --type merge -p '…'` | a low-level command, printed before it runs, quoted so that you can copy it |
| `🔎 polled: kubectl -n confluent get pods -l … -L controller-revision-hash` | a command a wait loop runs again and again (printed once) |
| `🔁 kafka-2 restarted on the new revision and Ready (18:14:13)` | the operator rolled that pod |
| `📊 after the upgrade (producer): 9827 records acked, 60 send errors` | the workload so far |
| `🕐 send errors per minute` | when each step hurt, and with which exception |
| `🔎 acked by the producer: 21346, records in topic day2: 21346, lag of the sink connector: 0` | the final check |

> [!NOTE]
> The producer does not retry on purpose: a real application with `retries` and `delivery.timeout.ms` rides through
> most of these errors. The send errors measure the disruption, they are not data loss: the final check proves that
> every acked record is there.

---

## 2. 🅰️ cp-ansible

### The commands, and what they run

| Command | What it runs (the 🔧 lines) |
| --- | --- |
| `playground ansible inventory set <yq path> <value>` | `yq -i '<path> = <value>' environment/ansible/inventory/hosts.yml`, then prints the diff |
| `playground ansible playbook [--rolling] [--limit h] [--tags t]` | `docker exec ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all [-e deployment_strategy=rolling] [--limit h]`, prints the PLAY RECAP and each failed host, then hands the cluster over to the playground commands (wrappers of the new binaries, client security of each host, CA) |
| `playground ansible upgrade --to <version>` | downloads the archive, sets `confluent_package_version` and `confluent_archive_file_source`, `docker exec ansible-controller ansible-galaxy collection install "confluent.platform:>=X.Y.0,<X.(Y+1).0" --force`, then the playbook with `deployment_strategy=rolling` |
| `playground ansible add-host <host>…` | `docker compose … --profile <p> up -d <host>` (the saved command of the environment), `yq` for the JMX port of the host in its group; then `playground ansible playbook --limit <host>` |

The playbook output is in `/tmp/playground-ansible-playbook.log` (`tail -f` it while it runs).

### What you see

Recorded locally (Docker Desktop, arm64), CP 8.4.1, cp-ansible 8.4.0; all five also pass in CI.

| Example | Key result |
| --- | --- |
| [`rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/rolling-upgrade.sh) | rolling upgrade: brokers restarted 42 s apart, 2 send errors, longest pause 0.1 s. The same broker change with the **default `parallel`** strategy: 3 brokers restarted in the same second, **259 send errors, 13 s without an ack**; with `--rolling`: 1 send error, 0.1 s. Feature level `CP-8.3-IV0B` until `kafka-features upgrade --feature confluent.metadata.version=141` |
| [`enable-sasl-ssl.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-sasl-ssl.sh) | listeners at each step (`CLIENT:SASL_SSL` added, connect moved to it, `INTERNAL:SASL_SSL`), 6 send errors over three rolling restarts for the migrated producer, the forgotten client: 0 acks once PLAINTEXT is closed, `Bootstrap broker broker:9092 … disconnected` |
| [`scale-out-brokers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/scale-out-brokers.sh) | 0 send errors while adding the brokers, `Replicas: 1` until `playground topic reassign`, 702 records acked with broker 1 down afterwards |
| [`static-to-dynamic-quorum.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/static-to-dynamic-quorum.sh) | `❌ controller: Detected a running static KRaft cluster (kraft.version=0)…` for the mistake, `kraft.version` 1 after `StaticToDynamicQuorumMigration`, voters 9991 (Leader), 9992 and 9993 (Follower) |
| [`enable-rbac.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-rbac.sh) | the application without a role binding: `TopicAuthorizationException: Not authorized to access topics: [day2]` as soon as RBAC is on (771 send errors in CI); the producer and the sink keep working with their role bindings; 49003 acked = 49003 in the topic = 49003 written by the sink (CI) |

The details, with the outputs of each step: [`other/cp-ansible-day2`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/cp-ansible-day2).

---

## 3. ☸️ Confluent for Kubernetes

### The commands, and what they run

| Command | What it runs (the 🔧 lines) |
| --- | --- |
| `playground cfk patch <kind>/<name> '<patch>' [--type json]` | `kubectl -n confluent patch <kind>/<name> --type merge -p '<patch>'`, then waits for the operator: 🔎 the generation of the statefulset (did the change restart anything?), its `updateRevision` and the `controller-revision-hash` of each pod (each pod restarted and Ready, printed as it rolls), the `status.phase` of the CR (`RUNNING`), then the events of the CR and its pods since the change |
| `playground cfk roll <kind>/<name>` | Kafka and KRaft: `kubectl patch … spec.podTemplate.annotations.kafkacluster-manual-roll=<new value>` (the only supported way to restart them: one pod at a time, with the health checks); other components: `kubectl rollout restart statefulset/<name>` |
| `playground cfk upgrade --to <cp version>` | for each CR, controllers first: `kubectl patch <kind>/<name> -p '{"spec": {"image": {"application": "<image>:<version>"}}}'`, waiting for each roll; then the images of the pods and `kafka-features describe` |
| `playground cfk operator upgrade --to <cfk version>` | the [CFK upgrade procedure](https://docs.confluent.io/operator/current/co-upgrade-cfk.html), step by step: `kubectl annotate <every CR> platform.confluent.io/block-reconcile=true`, the CRDs (`helm pull` + `kubectl apply --server-side`, before CFK 3.4.0), `helm upgrade --install confluent-operator … --version <chart> --reset-then-reuse-values`, `kubectl rollout status deployment/confluent-operator`, `kubectl patch <CR> spec.image.init` (staged), then `kubectl annotate <CR> platform.confluent.io/block-reconcile-` one component at a time, waiting for each roll. `--no-block-reconcile` skips the blocking: the classic mistake |

What `playground cfk operator upgrade --to 3.4.0` prints (abridged):

```text
☸️ CFK operator: confluent-for-kubernetes-0.1718.99 → confluent-for-kubernetes-0.2038.1 (CFK 3.4.0)
🔧 helm repo update confluentinc
⏸️ Step 1: block reconciliation on the 5 custom resources (platform.confluent.io/block-reconcile=true): the operator upgrade does not roll anything
🔧 kubectl -n confluent annotate kraftcontroller.platform.confluent.io/kraftcontroller platform.confluent.io/block-reconcile=true --overwrite
🔧 kubectl -n confluent annotate kafka.platform.confluent.io/kafka platform.confluent.io/block-reconcile=true --overwrite
…
📜 Step 2: CFK 3.4.0 manages its own CRDs (helm value manageCRDs, true by default): nothing to apply
⬆️ Step 3: helm upgrade confluent-operator --version 0.2038.1
🔧 helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --version 0.2038.1 --namespace confluent --reset-then-reuse-values
🔧 kubectl -n confluent rollout status deployment/confluent-operator --timeout=300s
✅ CFK operator docker.io/confluentinc/confluent-operator:0.2038.1
🧷 Step 4: stage the init container images (reconciliation still blocked: no roll yet)
🔧 kubectl -n confluent patch kraftcontroller/kraftcontroller --type merge -p '{"spec": {"image": {"init": "confluentinc/confluent-init-container:3.4.0"}}}'
…
▶️ Step 5: enable reconciliation again, one component at a time: each one rolls once (new operator and new init container)
🔧 kubectl -n confluent annotate kraftcontroller/kraftcontroller platform.confluent.io/block-reconcile-
🔎 polled: kubectl -n confluent get statefulset kraftcontroller -o 'jsonpath={.metadata.generation}'
⏳ kraftcontroller/kraftcontroller: CFK rolls the pods of statefulset kraftcontroller (generation 5 → 7), one at a time
🔎 polled: kubectl -n confluent get pods -l app=kraftcontroller,… -L controller-revision-hash
   🔁 kraftcontroller-2 restarted on the new revision and Ready (HH:MM:SS)
…
```

### What you see

Recorded on an EC2 instance (x86_64, 8 vCPUs, k3d), CP 8.4.1, 3 KRaft controllers, 3 brokers.

| Example | Key result |
| --- | --- |
| [`cfk-rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-rolling-upgrade.sh) | the 3 controllers, then the 3 brokers, connect and schema registry rolled one at a time (≈100 s per broker): **3 send errors, longest pause 0.2 s**. Feature level `CP-8.3-IV0B` until `kafka-features upgrade`. The merge patch of `configOverrides`: 8 overrides → `["log.retention.hours=72"]`. 21346 acked = 21346 in the topic, sink lag 0 |
| [`cfk-operator-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-operator-upgrade.sh) | without blocking reconciliation: **16 pod stops** (every pod twice: when the new operator starts, then for the init containers), and each controller restarted in the same second as a broker (`kraftcontroller-2` and `kafka-2` at 18:31:21). With the procedure: **8 pod stops**, one component at a time. 33285 acked = 33285 in the topic, every pod on `confluent-init-container:3.4.0` |

The details: [`other/cfk-day2`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/cfk-day2).

---

## 4. cp-ansible and CFK side by side

| | 🅰️ cp-ansible | ☸️ CFK |
| --- | --- | --- |
| who restarts the brokers | the playbook, `deployment_strategy`: **`parallel` by default** (every host at once), `rolling` on request | the operator, always one pod at a time, with its health checks (under-replicated partitions) |
| a property change | inventory + playbook (`--limit`, `--tags`) | a change of the CR: the operator rolls what needs it |
| upgrade Confluent Platform | `confluent_package_version` + the collection of that version + playbook `rolling` | the image tag of each CR, controllers first |
| upgrade the deployment tool | `ansible-galaxy collection install` (no restart by itself) | `helm upgrade` of the operator: rolls every component unless reconciliation is blocked; CRDs (before 3.4.0) and init containers to update |
| restart without a change | `confluent.platform.restart` playbook | `kafkacluster-manual-roll` annotation (Kafka, KRaft), `kubectl rollout restart` (others) |
| feature level after an upgrade | not finalized: `kafka-features upgrade` | not finalized: `kafka-features upgrade` |
| playground commands | `playground ansible playbook\|inventory\|add-host\|upgrade` | `playground cfk patch\|roll\|upgrade\|operator upgrade` |

---

## 5. Findings worth knowing (from these runs)

- **cp-ansible restarts every host at once by default.** A broker change applied with `confluent.platform.all` and
  no `deployment_strategy`: 3 brokers restarted in the same second, 259 send errors, 13 s without an ack (the
  brokers of the example hold little data: with real data every partition is offline for minutes). Use
  `-e deployment_strategy=rolling` (`playground ansible playbook --rolling`).
- **A CFK operator upgrade rolls everything, twice, unless reconciliation is blocked.** `helm upgrade` alone: every
  pod restarts when the new operator starts (controllers and brokers together), then again for the new init
  containers. The procedure (block reconcile, stage the init containers, enable reconcile one component at a time)
  gives one roll per component.
- **`helm upgrade --reuse-values` keeps the old operator image.** It reuses the computed values of the old release,
  `image.tag` included: chart `confluent-for-kubernetes-0.1718.99` deployed, operator still `confluent-operator:0.1718.10`,
  nothing upgraded. Use `--reset-then-reuse-values`, or the values file with the new `image.tag`.
- **One KRaft controller makes its roll an outage for `acks=all` producers.** Same CFK upgrade with one controller:
  355 send errors and 17.7 s without an ack, nearly all `NotEnoughReplicasException` in the minute the controller
  restarted (the brokers can't heartbeat, the ISR shrinks below `min.insync.replicas`). With 3 controllers: 3 errors,
  0.2 s.
- **A JSON merge patch of `configOverrides` replaces the list.** Add an item with a JSON patch instead
  (`playground cfk patch kafka/kafka '[{"op": "add", "path": "/spec/configOverrides/server/-", "value": "…"}]' --type json`).
- **A CFK change applied right after a roll may not reach the brokers.** In 2 runs out of 3, the CR, the ConfigMap and
  the file of the pods had the change, the operator logged "The current revision … is equal to the desired revision",
  the running brokers kept the old value. Check the running value (`kafka-configs --describe --all --entity-type
  brokers --entity-name 0`) and `playground cfk roll kafka/kafka` when they differ.
- **Neither cp-ansible nor CFK finalizes the feature level.** After the upgrade `confluent.metadata.version` stays at
  the old version until `kafka-features upgrade` (`--release-version` takes the Apache Kafka version: CP 8.4 is
  Kafka 4.4).
- **RBAC with cp-ansible:** an inventory that sets `config.providers` in `kafka_connect_custom_properties` replaces
  the `secret` provider of RBAC: the REST API of connect answers 404 on every endpoint, nothing in the logs (fixed in
  the inventory the ansible environment generates).

---

## 6. Recipes for support cases

| Customer report | What to run |
| --- | --- |
| "our producers failed while cp-ansible upgraded the cluster" | `other/cp-ansible-day2/rolling-upgrade.sh`: compare their `deployment_strategy` with the `parallel` and `rolling` steps; on their inventory: `playground run -f <example> --environment ansible --ansible-inventory <hosts.yml>`, then `playground ansible upgrade --to <version>` |
| "we enabled TLS / SASL and some applications stopped" | `other/cp-ansible-day2/enable-sasl-ssl.sh`: the forgotten client, its `disconnected` loop or `OutOfMemoryError` |
| "we enabled RBAC with cp-ansible and an application is denied / connect answers 404" | `other/cp-ansible-day2/enable-rbac.sh`, and the `config.providers` finding above |
| "we upgraded CP with CFK, what should the clients see?" | `other/cfk-day2/cfk-rolling-upgrade.sh`, or `playground cfk upgrade --to <version>` on a running cfk environment |
| "after the CFK upgrade every component restarted, some twice" | `playground cfk operator upgrade --to <version> --no-block-reconcile` (what they did) against `playground cfk operator upgrade --to <version>` (the procedure); `other/cfk-day2/cfk-operator-upgrade.sh` |
| "we ran helm upgrade, the operator still runs the old version" | `helm -n confluent get values confluent-operator --all \| grep tag`: `--reuse-values` kept the old `image.tag` |
| "our configOverrides disappeared" / "the brokers don't have the new value" | `playground cfk patch` with a merge patch shows the list replaced; compare the file of the pod and the running broker; `playground cfk roll kafka/kafka` |
| "how do I restart the brokers of a CFK cluster?" | `playground cfk roll kafka/kafka` (the `kafkacluster-manual-roll` annotation, never `kubectl delete pod` or `kubectl rollout restart` on Kafka) |

See also: [🍪 Deep dive cp-ansible](/deep-dive-ansible.md), [🍪 Deep dive Confluent for Kubernetes](/deep-dive-cfk.md),
[☁️ AWS EC2 instances](/deep-dive-ec2.md) (the CFK examples need about 24 GB: an EC2 instance runs them comfortably).
