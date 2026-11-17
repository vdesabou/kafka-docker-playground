# CFK day-2 operations

## Objective

Changes on a **running** cluster deployed by Confluent for Kubernetes (CFK), replayed step by step while a workload
runs through them: what the clients see at each step, what the classic mistake looks like, and a check at the end
that no record was lost. They follow the procedures CFK documents, with the
[`playground cfk`](https://kafka-docker-playground.io/#/deep-dive-cfk) commands, on the
[cfk environment](../../environment/cfk/) (k3d, 3 KRaft controllers, 3 brokers, schema registry, connect).

Every low-level command is printed before it runs (`🔧 kubectl …`, `🔧 helm …`, `🔧 docker exec ansible-controller
ansible-playbook …`, and `🔎 polled: …` for what a wait loop checks), quoted so that it can be replayed by hand. The
overview of all the day-2 examples, cp-ansible and CFK side by side, the findings and the recipes for support cases:
[🔁 Day-2 operations](https://kafka-docker-playground.io/#/day-2-operations).

The workload (`cfk-day2-utils.bash`):

- `kafka-verifiable-producer` in its own pod (`day2-client`, not managed by CFK: the pods of CFK are rolled by the
  changes), 20 records/s, `acks=all`, **no retries**: every leader move is a send error, so the disruption of each
  step is visible
- the FileStream sink connector on the same topic
- at the end: every acked record is in the topic, and the sink connector has no lag

| Example | Change | The classic mistake it shows |
| --- | --- | --- |
| `cfk-rolling-upgrade.sh` | CP 8.3.2 → the default CP version (or `--tag`), `playground cfk upgrade` | the feature level is not finalized by CFK; a JSON merge patch of `configOverrides` replaces the whole list |
| `cfk-operator-upgrade.sh` | CFK 3.3.0 → 3.3.1 with `helm upgrade` only, then 3.3.1 → 3.4.0 with the CFK upgrade procedure (`playground cfk operator upgrade`) | reconciliation not blocked: every component rolls as soon as the new operator starts, the controller and the brokers at the same time, then a second time for the init containers |

Each example starts its own cfk environment and takes 20 to 30 minutes. They need the cfk environment (k3d, kubectl,
helm): with another `PLAYGROUND_ENVIRONMENT` they are skipped (exit 111).

## How to run

```bash
playground run -f other/cfk-day2/cfk-rolling-upgrade.sh --environment cfk
playground run -f other/cfk-day2/cfk-operator-upgrade.sh --environment cfk
```

`cfk-rolling-upgrade.sh` goes from 8.3.2 (`DAY2_OLD_VERSION`) to the CP version of the run: `--tag` for another
target. `cfk-operator-upgrade.sh` uses `DAY2_OLD_CFK` (3.3.0), `DAY2_MID_CFK` (3.3.1) and `DAY2_NEW_CFK` (3.4.0).

The same commands work by hand on any cfk environment:

```bash
playground cfk patch kafka/kafka '[{"op": "add", "path": "/spec/configOverrides/server/-", "value": "num.io.threads=16"}]' --type json
playground cfk upgrade --to 8.4.1
playground cfk operator upgrade --to 3.4.0
```

## What you see

Recorded on an EC2 instance (x86_64, 8 vCPUs), CP 8.4.1.

### `cfk-rolling-upgrade.sh`

```text
⏳ kraftcontroller/kraftcontroller: CFK rolls the pods of statefulset kraftcontroller (generation 1 → 3), one at a time
   🔁 kraftcontroller-2 restarted on the new revision and Ready (18:10:14)
   🔁 kraftcontroller-1 restarted on the new revision and Ready (18:11:49)
   🔁 kraftcontroller-0 restarted on the new revision and Ready (18:13:29)
   🔁 kafka-2 restarted on the new revision and Ready (18:14:13)
   🔁 kafka-1 restarted on the new revision and Ready (18:15:52)
   🔁 kafka-0 restarted on the new revision and Ready (18:17:33)
   🔁 connect-0 restarted on the new revision and Ready (18:18:59)
   🔁 schemaregistry-0 restarted on the new revision and Ready (18:20:13)
🔁 during the rolling upgrade: 3 send errors (kafka-verifiable-producer does not retry: a leader move during a broker restart is an error), longest time without an ack 0.2s
Feature: confluent.metadata.version  SupportedMinVersion: CP-7.3-IV3  SupportedMaxVersion: CP-8.4-IV2A  FinalizedVersionLevel: CP-8.3-IV0B   <- after the upgrade
⬆️ kafka-features upgrade --feature confluent.metadata.version=141
configOverrides.server before: ["offsets.topic.replication.factor=1","transaction.state.log.replication.factor=1",…,"auto.create.topics.enable=true"]
🩹 kubectl patch kafka/kafka --type merge -p '{"spec": {"configOverrides": {"server": ["log.retention.hours=72"]}}}'
configOverrides.server after: ["log.retention.hours=72"]
🩹 kubectl patch kafka/kafka --type json -p '[{"op": "add", "path": "/spec/configOverrides/server/-", "value": "num.io.threads=16"}]'
🔎 num.io.threads of broker 0: 16 in the kafka.properties of kafka-0, 16 in the running broker
🔎 acked by the producer: 21346, records in topic day2: 21346, lag of the sink connector: 0
✅ no record lost: every acked record is in the topic and was consumed by the sink connector
```

CFK rolls one pod at a time (about 100 seconds per broker here), controllers first, and waits for each one to be
ready: there is no equivalent of the `parallel` strategy of cp-ansible. The feature level stays at the old version
until `kafka-features upgrade`, like with cp-ansible.

Good to know:

- with **one** KRaft controller (the default of the cfk environment), the roll of the controller is the hard part:
  in one run, 355 send errors and 17.7 s without an ack, nearly all `NotEnoughReplicasException` in the minute the
  controller restarted (the brokers cannot heartbeat, the ISR shrinks below `min.insync.replicas`). With 3
  controllers (`ENABLE_CONTROLLER_NODES=1`, what the examples use): 3 send errors, 0.2 s. The example prints the send
  errors per minute and exception
- step 6 checks that the brokers run a change applied right after a roll. In 2 runs out of 3, CFK wrote it to the
  ConfigMap (and the file of the pods) but did not roll the brokers ("The current revision … is equal to the desired
  revision" in the operator log): the brokers kept the old value until `playground cfk roll kafka/kafka` (annotation
  `kafkacluster-manual-roll`, the supported way to restart Kafka). The example rolls them when that happens

### `cfk-operator-upgrade.sh`

```text
⚠️ reconciliation not blocked (--no-block-reconcile): the new operator reconciles every custom resource as soon as it starts, all components roll at the same time
✅ CFK operator docker.io/confluentinc/confluent-operator:0.1718.99
   kraftcontroller-2 stopped 2 time(s): 18:31:21 18:36:23     <- the new operator starts: kraftcontroller-2, kafka-2, connect-0 and schemaregistry-0 in the same second
   kafka-2 stopped 2 time(s): 18:31:21 18:40:36
   connect-0 stopped 2 time(s): 18:31:20 18:44:40
   schemaregistry-0 stopped 2 time(s): 18:31:20 18:45:50
   kraftcontroller-1 stopped 2 time(s): 18:33:01 18:38:13     <- then each controller with a broker
   kafka-1 stopped 2 time(s): 18:33:02 18:42:16
   …                                                          <- the second time: the new init container images
💥 without blocking reconciliation: … 16 pod stops, 4 send errors, longest time without an ack 0.5s
⏸️ Step 1: block reconciliation on the 5 custom resources (platform.confluent.io/block-reconcile=true): the operator upgrade does not roll anything
📜 Step 2: CFK 3.4.0 manages its own CRDs (helm value manageCRDs, true by default): nothing to apply
✅ CFK operator docker.io/confluentinc/confluent-operator:0.2038.1
▶️ Step 5: enable reconciliation again, one component at a time: each one rolls once (new operator and new init container)
   kraftcontroller-2 stopped 1 time(s): 18:47:26
   kraftcontroller-1 stopped 1 time(s): 18:49:07
   kraftcontroller-0 stopped 1 time(s): 18:50:47
   kafka-2 stopped 1 time(s): 18:51:28
   …
🔁 with the procedure: one roll per component, one component at a time: 8 pod stops, 4 send errors, longest time without an ack 0.1s
🔎 acked by the producer: 33285, records in topic day2: 33285, lag of the sink connector: 0
🧷 init container images of the pods: confluentinc/confluent-init-container:3.4.0
```

Without blocking reconciliation, every pod restarts twice, and a controller and a broker restart together. The
brokers of the example hold little data and are back in seconds, so the clients barely notice (4 send errors either
way here): with real data a broker takes minutes to start, and two rolls of every component in a row, controllers and
brokers at the same time, are what customers report after a CFK upgrade. The example checks the number of pod stops,
which does not vary from run to run.

The procedure is the one of
[Upgrade Confluent for Kubernetes](https://docs.confluent.io/operator/current/co-upgrade-cfk.html): reconciliation
blocked on every custom resource, CRDs (CFK before 3.4.0: helm never upgrades them), `helm upgrade`, init container
images staged, reconciliation enabled again. `playground cfk operator upgrade` enables it one component at a time,
controllers first, and waits for each roll.

Good to know: `helm upgrade --reuse-values` keeps the computed values of the old release, the `image.tag` of the
operator included: the new chart runs the **old** operator image, and nothing changes. `playground cfk operator
upgrade` uses `--reset-then-reuse-values` (the defaults of the new chart, plus the values given at install) and checks
the image of the operator after the upgrade.
