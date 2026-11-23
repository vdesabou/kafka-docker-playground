# 🧹 Cleanup and scheduled jobs

Examples leave things behind: billable resources in Confluent Cloud, AWS, GCP and Azure, EC2 instances still running,
and gigabytes of images on the disk of the container engine. This page lists, in one place, the commands that clean
them up on demand and the jobs the playground can schedule to do it by itself. Part of the
[🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> Turn on the jobs once, then forget about them:
>
> ```bash
> playground cloud-resources nightly-cleanup enable --resource ccloud --resource aws --resource gcp --resource azure
> playground ec2 auto-stop enable
> playground docker-cleanup enable
> playground forgotten-environment enable
> playground cloud-resources cost-reminder enable --resource ccloud --resource aws --resource azure
> ```
>
> Each one first shows what it would remove (or, for the reminder, what it finds) now, so you see the effect before
> the first scheduled run.

## 🗺️ At a glance

| What is left behind | Costs | On demand | Automatically |
| --- | --- | --- | --- |
| Confluent Cloud connectors `*_<user>`, `pg-<user>-sa-*` environments, topics on shared clusters | 💰 | `playground cloud-resources cleanup --resource ccloud` | `playground cloud-resources nightly-cleanup enable` (every night, 02:00) |
| AWS / GCP / Azure resources of the examples (Kinesis, SQS, Redshift, DynamoDB, GCS, BigQuery, Spanner, Bigtable, resource groups…) | 💰 | `playground cloud-resources cleanup --resource aws\|gcp\|azure` | `nightly-cleanup enable --resource aws --resource gcp --resource azure` |
| EC2 instances created with `playground ec2 create` | 💰 | `playground ec2 stop`, `playground ec2 delete` | `playground ec2 auto-stop enable` (every evening, 20:00, idle ones) |
| GitHub Codespaces | 💰 | `playground codespace stop`, `playground codespace delete` | stops by itself after 30 minutes idle (GitHub) |
| Old Confluent Platform images, dangling images, build cache | 💾 | `playground remove-cp-docker-images`, `playground remove-all-docker-images` | `playground docker-cleanup enable` (every Sunday, 10:00) |
| Containers and volumes of the running example | 🔋 | `playground stop`, `playground container kill-all` | the next `playground run` stops the previous example; `playground forgotten-environment enable` notifies (every evening, 19:00) when one runs with nobody using it, never stops it |

To see what is still there:

```bash
playground status                         # the example, and a 💸 reminder for each ec2 instance still running
playground cloud-resources ccloud list    # what still runs for you in Confluent Cloud, org-wide (--json)
playground cloud-resources aws list       # same for AWS (azure list for Azure)
playground cloud-resources ccloud costs   # what it cost (aws costs, azure costs, costs-history)
playground cloud-resources cost-reminder run   # your cost of the last 7 days in each cloud, and the connectors still running
playground ec2 list                       # your instances: anything not 🛑stopped bills compute
docker system df                          # disk of the container engine: images, build cache, volumes
```

## ⏰ Scheduled jobs

| Job | Enable | When (default) | What it does | Log |
| --- | --- | --- | --- | --- |
| 🌙 Nightly cloud cleanup | `playground cloud-resources nightly-cleanup enable` (`--time`, `--resource`) | every day at 02:00 | `cloud-resources cleanup --force --nightly`: in Confluent Cloud what is billed or clutters a shared cluster; in AWS / GCP / Azure (with `--resource`) what `cleanup` deletes | `nightly-cleanup.log` |
| ⏰ EC2 auto-stop | `playground ec2 auto-stop enable` (`--time`, `--idle-minutes`) | every day at 20:00 | stops your `pg-<user>-*` instances still running and idle (CPU under 5% for `--idle-minutes`, default 60) | `ec2-auto-stop.log` |
| 🧽 Docker cleanup | `playground docker-cleanup enable` (`--day`, `--time`, `--older-than`, `--max-build-cache`) | every Sunday at 10:00 | old Confluent Platform versions (`--older-than 60` days), dangling images, build cache above `--max-build-cache` GB (10) | `docker-cleanup.log` |
| 🔔 Forgotten environment | `playground forgotten-environment enable` (`--time`, `--idle-hours`) | every day at 19:00 | **notifies only**, never stops anything: containers running, none started and no playground activity (playground.ini, playground-run-history of the checkout that started them) for `--idle-hours` (3) | `forgotten-environment.log` |
| 💸 Cost reminder | `playground cloud-resources cost-reminder enable` (`--day`, `--time`, `--resource`, `--threshold`, `--days`) | every Monday at 09:00 | **read-only**: the cost of your resources over the last `--days` (7) in Confluent Cloud (by name: `*_<user>`, `pg-<user>-*`), AWS and Azure (tag `cflt_managed_id=<user>`), what still runs for you; notifies when the cost reaches `--threshold` USD (50), a connector is RUNNING, or a cloud could not be checked | `cost-reminder.log` |
| 👀 Log bundle watch | `playground analyze watch --install-launch-agent` | at every login, always running | analyzes every new log bundle, dump or capture that lands in `~/Downloads` | `~/Library/Logs/playground-analyze-watch.log` |

Every scheduled job has the same three subcommands, plus `run` for the ones that act on a schedule:

```bash
playground ec2 auto-stop status     # scheduled?, when, with which options, and the last lines of its log (--lines)
playground ec2 auto-stop disable    # remove the schedule (the log is kept)
playground ec2 auto-stop run --dry-run   # what the job would do now (also: playground docker-cleanup run --dry-run)
playground cloud-resources cost-reminder run   # read-only jobs have no --dry-run (also: playground forgotten-environment run)
```

For the nightly cloud cleanup, the dry run is `playground cloud-resources cleanup --resource ccloud --nightly --dry-run`.
The log bundle watch is removed with `playground analyze watch --uninstall-launch-agent`.

### How they run

- **macOS**: a launchd agent, `~/Library/LaunchAgents/io.kafka-docker-playground.<job>.plist`, with its log in
  `~/Library/Logs/kafka-docker-playground/<job>.log`. When the Mac is asleep at that time, launchd runs the job when it
  wakes up. What each run did is shown in a macOS notification.
- **Linux**: a crontab line tagged `# kafka-docker-playground <job>`, with its log in
  `~/.local/state/kafka-docker-playground/<job>.log` (`$XDG_STATE_HOME`). A machine that is off at that time skips the
  run.
- **Running `enable` again** changes the time or the options: it replaces the schedule, never adds a second one.
- **The job runs the `playground` of the checkout you enabled it from, with the `PATH` of that shell.** Enabled from a
  worktree you then remove, the job fails: run `enable` again from the main checkout. After installing a tool the job
  needs (`aws`, `az`, `jq`), run `enable` again so that its `PATH` is picked up.
- **Nobody answers at night.** No job asks a question or opens a browser. When credentials can't be read without a
  prompt, that part is skipped with a notification and the rest still runs:
  - Confluent Cloud: keep the `confluent` CLI logged in (`confluent login --save`).
  - AWS: `~/.aws/credentials`, not an SSO session that expires.
  - Azure: a service principal (`AZ_CLIENT_ID`, `AZ_CLIENT_SECRET`, `AZ_TENANT_ID` in `playground secrets`) or a saved
    `az login` session.
  - 1Password secrets backend: a service account token ([Setup B of the secrets deep dive](/deep-dive-secrets.md)), otherwise the secrets store is not read
    at night (it would wait for Touch ID).

To list every job installed on this machine:

```bash
ls ~/Library/LaunchAgents/io.kafka-docker-playground.*      # macOS
launchctl list | grep kafka-docker-playground               # macOS: loaded agents, with the exit code of the last run
crontab -l | grep "# kafka-docker-playground"               # Linux
```

## ☁️ Cloud resources

`playground cloud-resources cleanup` deletes what the examples created in AWS, GCP, Azure, Confluent Cloud and the
Salesforce test orgs, scoped to names that contain `pg` and your user name. It asks before each deletion, unless
`--force`. Start with `--dry-run`:

```bash
playground cloud-resources cleanup --dry-run                    # everything, nothing deleted
playground cloud-resources cleanup --resource aws --dry-run     # one cloud (--resource is repeatable)
playground cloud-resources cleanup --resource ccloud            # then for real, confirming each deletion
```

The **nightly cleanup** runs the same command every night, with two limits:

- In Confluent Cloud, it only deletes what is billed or clutters a shared cluster: the connectors `*_<user>` with their
  dlq/success/error topics, the `pg-<user>-sa-*` environments, and the topics your runs recorded on shared clusters. It
  keeps your own `pg-<user>-*` clusters ([`playground account ccloud setup`](/toolkit-fully-managed.md)) and their topics, and
  never deletes service accounts or API keys: run `cleanup --resource ccloud` yourself for those.
- AWS, GCP and Azure are cleaned up only when you add them with `--resource`. Salesforce is not offered, because
  nothing there is billed.

> [!WARNING]
> The resources of an example still running at that time are deleted too (its connectors, its buckets). Pick a time
> when you don't run examples, or `disable` the job for a long overnight run.

More in the [🍪 deep dive on fully managed connectors](/deep-dive-fully-managed.md) (costs and cleanup).

## 🖥️ EC2 instances and Codespaces

An EC2 instance is billed while it runs. Its disk is billed until the instance is deleted.

```bash
playground ec2 stop                       # compute no longer billed, the disk and your work are kept; ec2 start later
playground ec2 sync-repro-folder ec2-to-local && playground ec2 delete --instance pg-<user>-<suffix>   # for good
playground ec2 auto-stop enable           # every evening: stop the idle ones still running
```

**EC2 auto-stop** stops every instance `pg-<user>-*` still running, and keeps an instance when one of these is true:

- it is busy: its CloudWatch `CPUUtilization` reached 5% in the last `--idle-minutes`, so a run or benchmark left in
  `tmux` goes on
- it was started less than `--idle-minutes` ago
- CloudWatch has no data for it: nothing proves it is idle
- it has the tag `playground-keep-running=true`:
  `aws ec2 create-tags --resources <instance id> --tags Key=playground-keep-running,Value=true`

`--idle-minutes 0` stops instances whatever they are doing.

```bash
playground ec2 auto-stop run --dry-run
# 🔎 dry-run: listing what would be stopped, nothing is stopped
# 🔥 keeping pg-<user>-123456 (i-…): busy, CPU reached 38% in the last 60 minutes
```

A **GitHub Codespace** stops by itself after 30 minutes idle. `playground codespace stop` stops it now, and
`playground codespace delete` stops the storage billing. More in the [🍪 deep dive on EC2](/deep-dive-ec2.md).

## 🐳 Disk of the container engine

Each Confluent Platform version you run keeps a dozen images on disk (several GB). The connect images patched or
built locally leave dangling images and build cache behind. A full disk then makes examples fail in confusing ways.

| Command | Removes | Never removes |
| --- | --- | --- |
| `playground remove-cp-docker-images` | the CP versions you pick in a table (size, last use), or `--older-than <days>`, `--keep-latest-patch`, `--version 7.9`, `--all` (`--dry-run`, `--yes`) | the default TAG, the TAG of the current run, a version used by a container |
| `playground docker-cleanup run` | CP versions not used for `--older-than` days (60), dangling images, build cache above `--max-build-cache` GB (10) | anything a container or a build in progress uses, volumes |
| `playground remove-all-docker-images` | every image and volume, not only the playground's (everything is pulled again afterwards) | the Oracle database images (long to build) |

```bash
playground docker-cleanup run --dry-run
# 🧹 Confluent Platform versions not used for 60 days
# 🔎 dry-run, would run: docker image prune --force   # 27 dangling image(s), the ones used by a container are kept
# 🔎 dry-run, would run: docker builder prune --force --max-used-space 10GB   # build cache now: 73.02GB
playground docker-cleanup run
# ✅ freed 18.97GB (images 239.4GB → 231.1GB, build cache 73.02GB → 62.35GB)
# 🎓 51.92GB of the build cache are layers shared with images: freed with the images only (playground remove-cp-docker-images)
```

The layers of the build cache shared with images don't count towards `--max-build-cache`: they go when the images go.

## 🧩 The running example

| Command | What it does |
| --- | --- |
| `playground stop` | tears down the containers and volumes of the environment and of the example (data is not kept) |
| `playground container kill-all` | kills every container on the engine and prunes the volumes, other sessions' included |
| `playground cleanup-cloud-details` | forgets the Confluent Cloud details the playground cached, when it uses an unexpected cluster |

Forgot an environment running on a laptop? `playground forgotten-environment enable` checks every evening and sends a
macOS notification when containers run with nobody using them. It never stops them: another session, a long benchmark
or a repro can run on purpose.

```bash
playground forgotten-environment run
# 📂 /Users/me/kafka-docker-playground: connect-aws-s3-sink/s3-sink.sh (plaintext), last playground activity 6 h ago
# 🐳 11 container(s) running for 7 h, last one started 7 h ago
# 🔔 forgotten? s3-sink.sh: 11 container(s) up for 7 h, 6.3 GB of RAM, no playground activity for 6 h
# 👉 playground stop   # from the checkout that started it (not done for you: it may run on purpose)
```

> [!NOTE]
> With `playground config container-kill-all-before-run true` (default `false`), every `playground run` first kills
> **all** containers, those of another session or worktree included.
