# 🍪 Deep dive: fully managed connectors (Confluent Cloud)

The `ccloud/fm-*` examples run a fully managed connector in your own Confluent Cloud organization: the playground
creates (or reuses) an environment, a cluster, a service account, API keys and Schema Registry, then the same
`playground connector …` commands you use on a local worker drive the connector through the Confluent Cloud APIs.
This page is about what changes when there is no worker you can reach: names, waits, offsets, logs, DLQ, costs and
cleanup. Takes about 15 minutes to read, and the lab costs a few cents.

> [!TIP]
> Three video sessions cover the neighbours of this page:
> [🚚 Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed)
> (the Connector Migration Utility),
> [🏗️ Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform)
> and [👤 A fully managed connector with a service account loses an ACL](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl).
> This page covers the everyday commands: how the cluster is chosen, what each connector command does on Confluent
> Cloud, a hands-on lab and recipes for support cases.

| You want | Command |
| --- | --- |
| run a fully managed example | `playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh` |
| reuse your own cluster instead of creating one | `export ENVIRONMENT=… CLUSTER_NAME=… CLUSTER_CLOUD=… CLUSTER_REGION=… CLUSTER_CREDS=…` before the run |
| forget the cached cluster details | `playground cleanup-cloud-details` (nothing is deleted in Confluent Cloud) |
| create / update and wait for RUNNING | `playground connector create-or-update -c DatagenSource_$USER --wait << EOF … EOF` |
| the state, the error, the fix Confluent Cloud suggests | `playground connector status`, `playground connector error-recommendations -c <name>` |
| the logs of the connector | `playground connector logs -c <name>` (`--open`, `--wait-for-log "<text>"`) |
| what it is doing (no JMX) | `playground connector display-metrics-api -c <name>` |
| its offsets, change them | `playground connector offsets get\|alter\|reset -c <name>` (asynchronous) |
| its page in the console | `playground connector open-ccloud-connector-in-browser -c <name>` |
| the fully managed equivalent of a self-managed config | `playground connector translate`, `playground connector connect-migration-utility discovery\|migrate` |
| deploy it with Terraform | `playground connector create-or-update -c <name> --terraform << EOF … EOF` |
| run it with a service account and the ACLs of the documentation | `playground run -f <example> --ccloud-service-account`, then `playground rbac acl list\|delete\|create --connector <name>` |
| what you spent | `playground ccloud-costs-history`, `playground ccloud-costs` |
| delete what the playground created | `playground stop` in the example folder (`maybe_delete_ccloud_environment`), `playground cleanup-cloud-resources` |

---

## 1. Mental model (the 3 things to remember)

1. **One cluster per machine, cached.** `bootstrap_ccloud_environment` (the first line of every `ccloud/fm-*` example,
   instead of `start-environment`) either reuses a cluster or creates a full stack:
   - **your cluster**: `CLUSTER_NAME`, `ENVIRONMENT`, `CLUSTER_CLOUD`, `CLUSTER_REGION` and `CLUSTER_CREDS`
     (`<api key>:<secret>`, optionally `SCHEMA_REGISTRY_CREDS`) exported before the run;
   - **otherwise a new stack**: a service account, an environment `pg-${USER}-<service account>-<example>`, a **basic**
     cluster `pg-${USER}-cluster-<service account>` on **AWS `eu-west-2`** unless `CLUSTER_CLOUD` / `CLUSTER_REGION`
     are set, its API keys with full ACLs, and Schema Registry;
   - **the previous one**: the details are saved in `playground.ini` (`[ccloud]`) and the client configs in `.ccloud/`
     (`env.delta`, `librdkafka.delta`, `ak-tools-ccloud.delta`…). The next example asks
     `🙋 Use previously used ccloud cluster: … Continue (y/n)?`.

   Some examples need a given cloud or region (`bootstrap_ccloud_environment "aws" "us-east-1"`): with a cached cluster
   elsewhere, the example stops and tells you what to set. `playground cleanup-cloud-details` drops the cache when
   it points to a cluster that no longer exists.

2. **Same commands, other APIs, and three differences that bite.** Every `playground connector` command detects a
   fully managed connector (`🌤️🤖fully managed connector …` in its messages, with its `lcc-` id) and calls the Confluent Cloud
   Connect API through the `confluent` CLI instead of `localhost:8083`. What changes:
   - **names**: the connector name is free, but every example uses `<Type>_$USER` (`DatagenSource_vsaboulin`), so
     colleagues sharing an environment don't collide; the class is the **type** (`DatagenSource`, `S3_SINK`), not a
     Java class, and keys differ (`kafka.api.key`, `input.data.format`, `topics.dir`…);
   - **waits**: provisioning takes minutes. `create-or-update` only waits with `--wait` (up to 600 s, restarting the
     connector or its tasks when they fail while being provisioned); the examples call
     `wait_for_ccloud_connector_up <name> <seconds>` instead;
   - **asynchronous changes**: `offsets alter|reset` post a request and poll
     `offsets get-offsets-request-status`; there is no `connector stop` before (Confluent Cloud does it).

3. **It's billed, and the playground cleans up only what it created.** A basic cluster and a running connector cost
   money by the hour. `playground stop` in a `ccloud/fm-*` folder runs `maybe_delete_ccloud_environment`: it deletes
   the cluster **only if the playground created it** (no `CLUSTER_NAME` exported), and the environment only if it
   created it too (no `ENVIRONMENT`). Your own cluster and environment are never deleted. The examples delete their
   connector at the end, after `check_if_continue`.

**Local systems are reached through a tunnel.** When the connector reads or writes a container of the example (Postgres,
MongoDB, an HTTP server…), an `ngrok` service exposes it and the example reads the public endpoint from
`http://127.0.0.1:4040/api/tunnels`. That needs `NGROK_AUTH_TOKEN`, or `BORE_SERVER` and `BORE_SECRET`: with those set, the same
service opens the tunnels on a [bore](https://github.com/ekzhang/bore) server instead (image built from
[`tools/bore-tunnel`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/bore-tunnel), same API, no ngrok
quota). CI uses bore.

---

## 2. Choosing the cluster: `bootstrap_ccloud_environment`

```bash
# use an existing cluster (all five are required; SCHEMA_REGISTRY_CREDS optional)
export ENVIRONMENT=env-xxxxx CLUSTER_NAME=my-cluster CLUSTER_CLOUD=aws CLUSTER_REGION=eu-west-2 CLUSTER_CREDS="<key>:<secret>"
playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh

# create a new one somewhere else
export CLUSTER_CLOUD=gcp CLUSTER_REGION=europe-west1 CLUSTER_TYPE=basic
playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh
```

What it prints on a new stack:

```text
🛠👷‍♀️ CLUSTER_NAME is not set, a new Confluent Cloud cluster will be created...
🎓 If you wanted to use an existing cluster, set CLUSTER_NAME, ENVIRONMENT, CLUSTER_CLOUD, CLUSTER_REGION and CLUSTER_CREDS (also optionnaly SCHEMA_REGISTRY_CREDS)
CLUSTER_CLOUD and/or CLUSTER_REGION are not set, the cluster will be created 🌤 AWS provider and 🗺 eu-west-2 region
🔋 CLUSTER_TYPE is set with basic
```

Gotchas:

- **`confluent login` first** (CLI 4.32.0 or later): `This script requires confluent CLI to be logged in. Please
  execute 'confluent login' and run again.` On CI, the login uses `CONFLUENT_CLOUD_EMAIL` / `CONFLUENT_CLOUD_PASSWORD`.
- **With `CLUSTER_NAME` set, one missing variable stops the run** (`One mandatory environment variable to use your
  cluster is missing:` and the five values).
- **The cache wins over your intent**: a cluster deleted from the UI, another organization, an API key revoked: run
  `playground cleanup-cloud-details` and start again. Nothing is deleted in Confluent Cloud by it.
- **Per-cloud clusters**: `AWS_CLUSTER_NAME`, `GCP_CLUSTER_NAME`, `AZURE_CLUSTER_NAME` (with their `*_REGION`,
  `*_CLOUD`, `*_CREDS`) are used automatically for the `fm-aws*`, `fm-gcp*`, `fm-azure*` examples: set them once to
  keep a cluster per cloud.
- A new stack takes several minutes (cluster provisioning, API keys propagation, ACLs, Schema Registry); the wait for
  the cluster to be ready can take much longer when the `confluent` CLI is not logged in (`Error: not logged in`,
  then `giving up after 1 attempt` retries): run `confluent login --save` first.
- **The fully managed connector's API key is in its config** (`kafka.api.key`/`kafka.api.secret` from `$CLOUD_KEY` /
  `$CLOUD_SECRET`, set by `env.delta`): `show-config` masks it, `/tmp/config-<name>` doesn't.

---

## 3. Connector commands on Confluent Cloud

| Command | On a self-managed worker | On a fully managed connector |
| --- | --- | --- |
| `create-or-update` | `PUT /connectors/<c>/config`, waits by default | Connect API through `confluent`, waits only with `--wait` (600 s) |
| `status` | REST status, stack trace | status and the error message of the API; `error-recommendations` for the analysed stack trace |
| `logs` | container logs | `confluent connect logs <lcc> --level "ERROR\|WARN\|INFO"`: the last hours only, limited ([docs](https://docs.confluent.io/cloud/current/connectors/logging-cloud-connectors.html#using-ccloud-cli)) |
| `show-config` | what you sent (`/tmp/config-<c>`) | same; with `--force-rest-endpoint`, what Confluent Cloud returns: the API key and secret are **not returned at all**, and the keys it added appear (`cloud.environment`, `cloud.provider`, `kafka.endpoint`, `kafka.region`) |
| `offsets get` | KIP-875 REST, synchronous | Confluent Cloud offsets API |
| `offsets alter\|reset` | stop → change → resume | request posted, then `offsets get-offsets-request-status` until it's applied |
| `pause` / `resume` / `restart` / `delete` | REST | API (a restart of a task: `--task-id`) |
| `stop`, `log-level`, `debug …`, `analyze … -c` | ✅ | ❌ no worker to reach |
| `diagnose` | status + log digest + lag | status + `error-recommendations` + a check of the service account ACLs |
| `topic dlq inspect --connector` | `errors.deadletterqueue.topic.name` | `dlq-<lcc id>` by default (or its `errors.deadletterqueue.topic.name`, `${connector}` being the lcc id) |
| `display-metrics-api` | ❌ | Telemetry API: connector / task status and the non-zero metrics |
| `open-ccloud-connector-in-browser` | ❌ | the connector's page in the console |

Gotchas:

- **`--wait` or `wait_for_ccloud_connector_up`, never `sleep`**: a fully managed connector can be `PROVISIONING` for
  minutes, then fail transiently (Schema Registry API key not propagated yet: `401 API_KEY_NOT_FOUND`). The wait
  restarts it and its failed tasks instead of giving up (described from the code: not hit in the lab, where the
  connectors went from `🏭 PROVISIONING` to `RUNNING` in about 15 seconds).
- **`error-recommendations` returns nothing for a healthy connector, or for a config that failed validation**:
  `status` shows those errors.
- **Logs are the weakest signal**: no TRACE, a limited window, rate-limited. For "is it doing anything?", use
  `display-metrics-api` (records in/out, lag) and `topic consume`.
- **Not every fully managed connector supports the offsets API**: Datagen answers `403 Offset operations are not
  permitted`. Check the connector's page in the Confluent Cloud docs.
- **Offsets of a fully managed source are the connector's own format**, like on a worker: read them with `offsets get`
  before writing them. A sink's offsets are the consumer group `connect-<lcc id>`.
- **Names with `$USER`**: the connector of a colleague with the same name in the same environment is **updated**, not
  duplicated. Keep the `_$USER` suffix of the examples.
- **`--terraform`** writes `connector.tf` in `.terraform-playground/<name>-*/`, runs `terraform init/plan/apply`, puts
  secrets in `config_sensitive`; `connector delete` runs `terraform destroy` (the 🏗️ session).

---

## 4. Costs and cleanup

```bash
playground ccloud-costs-history                 # total per month since last year (--detailed for the lines) + HTML report
playground ccloud-costs --start-date 2026-10-01 --end-date 2026-10-23
playground connector delete --connector DatagenSource_$USER
playground stop                                 # in the example folder: maybe_delete_ccloud_environment
playground cleanup-cloud-resources              # resources left behind by examples (buckets, functions, connectors…)
```

Gotchas:

- **Costs show up after up to 72 hours**: `ccloud-costs` of today is not the bill of today.
- **`ccloud-costs-history` also writes an HTML report** in `/tmp/playground-cloud-costs` (`--output-dir`, `--no-open`): cost
  per month and per day, per product, environment and line type, the resources still billing (a cost on each of the last 3
  days with data, with a monthly estimate) and the details of each month. `playground run` of a `ccloud` example prints its
  link at the end (`--sample ccloud_dummy` to try it on dummy data); `cloud-resources aws|azure costs-history` write the
  same report for the AWS / Azure resources of the playground. When S3 costs something, the AWS one adds the Amazon S3
  details: cost and volume of each kind of S3 usage (storage, requests, retrieval fees, data sent to the Internet or to
  another region), per month and per destination, the tagged buckets (size, access logging, lifecycle) and hints
  (`cloud-resources aws costs-history --sample aws_dummy`). There is no cost per bucket: Cost Explorer needs the
  resource-level data of the payer account for that.
- **`playground stop` deletes the cluster the playground created**, with its topics and connectors, and keeps
  `ENVIRONMENT` / `CLUSTER_NAME` you exported. Run it in the `ccloud/fm-*` folder (its `stop.sh` calls
  `maybe_delete_ccloud_environment`).
- **External resources are the example's job**: buckets, tables, queues created by an `fm-*` example are deleted by
  its `cleanup_cloud_resources` trap at the end; an interrupted run can leave them: `playground cleanup-cloud-resources`
  (needs the cloud credentials of each provider).
- The connector is billed while it exists, RUNNING or not: delete it, don't just pause it.

---

## 5. Hands-on lab (≈10 min, a few cents)

The cheapest fully managed connector: Datagen, no external system. Log in with `confluent login` first.

**Step 1: the cluster, and a topic**

```bash
cd ccloud/fm-datagen-source
playground run -f fully-managed-datagen-source.sh        # creates or reuses the cluster, then the example's connector
# 🌱 CLUSTER_NAME is set, your existing Confluent Cloud cluster will be used...   (or the new stack lines)
# 🛠️ Creating 🌤️🤖fully managed connector DatagenSource_<user> … 🏭 PROVISIONING … 🟢 connector DatagenSource_<user> (lcc-…) is RUNNING
# ✅ RESULT: SUCCESS for fully-managed-datagen-source.sh
playground topic create --topic lab_pageviews --nb-partitions 1
```

**Step 2: a connector of your own, waited for**

```bash
playground connector create-or-update --connector LabDatagen_$USER --wait << EOF
{
  "connector.class": "DatagenSource",
  "name": "LabDatagen_$USER",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "kafka.topic": "lab_pageviews",
  "output.data.format": "JSON",
  "quickstart": "PAGEVIEWS",
  "max.interval": "1000",
  "tasks.max": "1"
}
EOF
# ⏳ waiting up to 600 seconds for connector LabDatagen_<user> (lcc-…) to be RUNNING
# 🟢 connector LabDatagen_<user> (lcc-…) is RUNNING            <- about 15 s here
playground connector status --connector LabDatagen_$USER
playground topic consume --topic lab_pageviews --min-expected-messages 5 --timeout 120
```

**Step 3: what you can see without a worker**

```bash
playground connector error-recommendations --connector LabDatagen_$USER
# ✅ No error recommendations available: the connector has no failure stack trace (healthy, or it failed only at config validation, …)
playground connector display-metrics-api --connector LabDatagen_$USER
# 📊 Connector metrics summary … 🔴 No non-zero metrics for this connector     <- the Metrics API lags a few minutes behind
playground connector offsets get --connector LabDatagen_$USER
# 🔥 Command failed with error code 403
# 🔥 Offset operations are not permitted                                    <- not every fully managed connector supports the offsets API (Datagen doesn't)
playground connector show-config --connector LabDatagen_$USER --force-rest-endpoint
# … "cloud.provider": "aws", "kafka.endpoint": "SASL_SSL://pkc-….confluent.cloud:9092", "kafka.region": …   <- no kafka.api.key / kafka.api.secret
playground connector logs --connector LabDatagen_$USER
# Found 4 log entries for connector lcc-…: INFO task-0 WorkerSourceTask{id=lcc-…-0} … Topic 'lab_pageviews' already exists.
```

**Step 4: clean up**

```bash
playground connector delete --connector LabDatagen_$USER
playground connector delete --connector DatagenSource_$USER                  # the example's one, if you didn't let it
playground topic delete --topic lab_pageviews
playground stop                                                              # deletes the cluster only if the playground created it
```

---

## 6. Recipes for support cases

| Customer question | Command |
| --- | --- |
| "here is our fully managed config" | the matching `ccloud/fm-*` example (`playground find-example "<type>" --category ccloud`), the customer's keys in its heredoc, `create-or-update --wait` |
| "our connector is FAILED" | `connector status`, then `connector error-recommendations`; `connector diagnose` adds the ACL check |
| "Missing write permission on topic(s)", our connector uses a service account | `playground run --ccloud-service-account`, delete the ACL the customer lacks with `rbac acl delete --connector`, restart, `connector diagnose` (👤 session) |
| "it's RUNNING but nothing arrives" | `display-metrics-api` (records in/out), `topic dlq inspect --connector <name>` (`dlq-<lcc id>`) |
| "skip a poison record / replay from an offset" | `connector offsets get`, then `offsets alter` (asynchronous, watch `get-offsets-request-status`) |
| "will our self-managed config work on Confluent Cloud?" | `connector translate` on the self-managed example run with `--environment ccloud`, or the Connector Migration Utility (🚚 session) |
| "we deploy with Terraform" | `create-or-update --terraform`: the same JSON becomes `connector.tf` (🏗️ session) |
| "which version of the connector runs in Confluent Cloud?" | `connector-plugin sourcecode -c confluentinc/<Type> --only-show-url` (employees, see the [connector plugins deep dive](/deep-dive-connector-plugin.md)) |
| "the example uses the wrong cluster" | `playground cleanup-cloud-details`, then export `CLUSTER_NAME`… or `CLUSTER_CLOUD` / `CLUSTER_REGION` |
| "how much did that test cost?" | `playground ccloud-costs-history --detailed` (72 h delay), its HTML report for the resources still billing |

---

## 7. Cheat sheet

```bash
# cluster: reuse yours, or let the playground create one (AWS eu-west-2, basic)
export ENVIRONMENT=… CLUSTER_NAME=… CLUSTER_CLOUD=… CLUSTER_REGION=… CLUSTER_CREDS="<key>:<secret>"
playground cleanup-cloud-details

playground connector create-or-update -c <Type>_$USER [--wait] [--terraform] << EOF … EOF
playground connector status|logs|show-config|delete -c <name>
playground connector error-recommendations|display-metrics-api|open-ccloud-connector-in-browser -c <name>
playground connector offsets get|alter|reset -c <name>    # + offsets get-offsets-request-status
playground topic dlq inspect --connector <name>           # dlq-<lcc id>
playground ccloud-costs-history [--detailed]
playground stop                                           # in the ccloud/fm-* folder
```

- One cached cluster per machine (`playground.ini` `[ccloud]`, `.ccloud/`); `cleanup-cloud-details` to forget it.
- Same `connector` commands, Confluent Cloud APIs: wait only with `--wait` (600 s), asynchronous offsets, no worker
  commands (`stop`, `log-level`, `debug`).
- Billed by the hour: delete the connector, `playground stop` deletes only what the playground created.
- Sources: `bootstrap_ccloud_environment` / `maybe_delete_ccloud_environment` / `wait_for_ccloud_connector_up` in
  [`utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh),
  [`commands/connector/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/connector),
  the example [`ccloud/fm-datagen-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-datagen-source).

---

**Links**

- 🎬 Video sessions: [🚚 Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed),
  [🏗️ Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform),
  [👤 A fully managed connector with a service account loses an ACL](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl)
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (the waits),
  [offsets and lag](/deep-dive-offsets-and-lag.md), [`connector diagnose` and the DLQ](/deep-dive-connector-troubleshooting.md),
  [connector plugins](/deep-dive-connector-plugin.md)
- 📖 [Confluent Cloud examples](/how-to-use?id=🌤️-confluent-cloud-examples) in How to Use
- 🧠 CLI reference: [playground connector](/playground%20connector), [playground cleanup-cloud-details](/playground%20cleanup-cloud-details),
  [playground ccloud-costs-history](/playground%20ccloud-costs-history)
