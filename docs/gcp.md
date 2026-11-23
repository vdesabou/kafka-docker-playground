# ☁️ GCP examples: set up a project

The GCP examples run against a **real Google Cloud project**:

- self-managed: `connect/connect-gcp-*` and `connect/connect-jdbc-gcp-bigquery-source` (Cloud Storage, Pub/Sub,
  BigQuery, Spanner, Bigtable, Cloud Functions, Dataproc, Firebase);
- fully managed: `ccloud/fm-gcp-*` and `ccloud/fm-debezium-gcp-spanner-source`.

Each example creates the resources it needs (bucket, topic, Spanner instance, Bigtable instance, Firestore database…)
and deletes them at the end. What it can't create is the access: the APIs must be enabled, and it needs a service
account key with the right roles, in `GCP_KEYFILE_CONTENT` (or a `keyfile.json` in the example folder), plus
`GCP_PROJECT`.

`playground account gcp setup` configures a project in one command. Only creating the project, with billing enabled, stays
manual. `playground account gcp check` tells you, in a few seconds, whether the stored key still works for every API the
examples use.

?> **TL;DR**: create a project with billing enabled, run `playground account gcp setup --project <project id>`, run an
example. No more `keyfile.json` to copy into each example folder. On a **shared project** where you were given a key,
run `playground account gcp setup --keyfile <key.json>` instead (see [Shared project](/gcp?id=🤝-shared-project-use-the-key-you-were-given)).

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| A **Google Cloud project with billing enabled** | the examples create buckets, topics, Spanner and Bigtable instances, Dataproc clusters in it | see [step 1](/gcp?id=_1-create-a-project-with-billing-enabled) |
| The **Owner** role on it (or Project IAM Admin + Service Account Admin + Service Usage Admin) | `setup` enables APIs, creates a service account and grants it roles | the creator of a project is its owner |
| **`gcloud`** on your machine, **or Docker** | `setup` runs gcloud; without it, the `google/cloud-sdk` image the examples already use | see [step 2](/gcp?id=_2-gcloud-optional) |
| `openssl`, `curl`, `jq` | key, login, JSON | usually there already (`brew install jq` on macOS) |

`check` needs neither gcloud nor Docker.

## 🚀 Step by step

### 1. Create a project with billing enabled

Create a project at [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate) and link
a billing account to it
([Billing → Link a billing account](https://console.cloud.google.com/billing/linkedaccount)). A new Google Cloud
account gets free trial credits. Spanner, Bigtable, Dataproc and Cloud Functions refuse to start without billing.

!> Use a **sandbox project**, not a shared or production one: the service account gets broad roles on the project
(see [what it configures](/gcp?id=what-it-configures)).

Many corporate organizations forbid service account keys (organization policy
`iam.disableServiceAccountKeyCreation`). If `setup` stops on it, use a project outside that organization.

### 2. gcloud (optional)

`setup` uses your `gcloud` when it is installed
([install guide](https://cloud.google.com/sdk/docs/install), or `brew install --cask google-cloud-sdk`). Otherwise it
runs the `google/cloud-sdk` image with Docker: then the login prints a link to open and asks for the verification code.

### 3. Run `playground account gcp setup`

```bash
playground account gcp setup --project my-sandbox-project
```

A browser opens once: log in with the account that owns the project. The command then does the rest, in a minute or
two on a new project:

```text
🌐 log into Google Cloud in the browser, with the account that owns the project
👤 account you@example.com
🗂️ project my-sandbox-project
🔌 enabling the APIs of the examples (a minute the first time)
🤖 creating service account kdp-playground@my-sandbox-project.iam.gserviceaccount.com
🎭 kdp-playground@my-sandbox-project.iam.gserviceaccount.com has the 13 roles of the examples (13 granted now)
🔑 creating a key for kdp-playground@my-sandbox-project.iam.gserviceaccount.com
🔑 key 3f2a91c07b4e… saved in ~/.config/kafka-docker-playground/gcp-keyfile.json
✅ the key of kdp-playground@my-sandbox-project.iam.gserviceaccount.com can log in
💾 stored GCP_PROJECT and GCP_KEYFILE_CONTENT
⏳ waiting for the 13 new roles to apply (up to 2 minutes, max 180 seconds)
🩺 what the key can do in my-sandbox-project:
✅ login works
✅ Cloud Storage
…
🎉 project my-sandbox-project is ready for the GCP examples
🩺 check it any time with: playground account gcp check
```

It ends with `playground account gcp check` (see [below](/gcp?id=🩺-when-something-stops-working-playground-account-gcp-check)), retried until
the roles it just granted apply: IAM takes up to 2 minutes.

The login happens in a gcloud configuration of its own
(`~/.config/kafka-docker-playground/gcloud`), so your own gcloud login and default project stay as they are. Already
logged in with gcloud? Pass `--account you@example.com` to skip the browser.

#### What it configures

| In the project | What for |
| --- | --- |
| APIs: Cloud Storage, Pub/Sub, BigQuery (+ Storage API), Spanner, Bigtable (+ Admin), Firestore, Realtime Database, Cloud Functions, Cloud Run, Dataproc, Compute Engine, IAM, Resource Manager, Service Usage, Cloud Billing | the APIs the examples call |
| Service account `kdp-playground` | the identity of the connectors and of the `gcloud` commands of the examples |
| … with the roles `storage.admin`, `pubsub.admin`, `bigquery.admin`, `spanner.admin`, `bigtable.admin`, `datastore.owner`, `firebasedatabase.admin`, `cloudfunctions.invoker`, `cloudfunctions.viewer`, `run.invoker`, `dataproc.editor`, `iam.serviceAccountUser`, `resourcemanager.projectIamAdmin` | create and delete the resources of each example; the Firestore sink grants `roles/datastore.user` to the Firestore user it creates |
| A key, saved in `~/.config/kafka-docker-playground/gcp-keyfile.json` (mode `600`) | stored as `GCP_KEYFILE_CONTENT`, the format the examples and CI use |

`playground account gcp setup --dry-run` prints this list for your project without changing anything.

Running it again on the same project changes nothing: the service account and its roles are reused, and so is the
key while the saved file still matches a key of the service account (`--new-key` creates a new one).

### 4. Check, then run an example

```bash
playground account gcp check
playground run -f connect/connect-gcp-gcs-sink/gcs-sink.sh
```

`playground run` loads `GCP_PROJECT` and `GCP_KEYFILE_CONTENT` from your secrets store for every GCP example.

## 🤝 Shared project: use the key you were given

On a project shared by a team, you usually can't create service accounts or keys: someone gives you a service account
key file instead. `setup --keyfile` takes it from there, without gcloud, and changes nothing in the project:

```bash
playground account gcp setup --keyfile ~/Downloads/my-project-3f2a91c07b4e.json
```

```text
✅ the key of team-playground@shared-project.iam.gserviceaccount.com can log in
🔑 key 3f2a91c07b4e… saved in ~/.config/kafka-docker-playground/gcp-keyfile.json
💾 stored GCP_PROJECT and GCP_KEYFILE_CONTENT
🩺 what this key can do in shared-project:
🔑 OAuth login of team-playground@shared-project.iam.gserviceaccount.com (key 3f2a91c07b4e…, from ~/.config/kafka-docker-playground/gcp-keyfile.json)
✅ login works
✅ Cloud Storage
…
🎉 project shared-project is ready for the GCP examples
```

`GCP_PROJECT` defaults to the `project_id` of the key (`--project` to change it). The `check` that ends the command
tells you which examples the key can run. A disabled API or a missing role is for the owner of the project to fix: the
line says which one.

## 🩺 When something stops working: `playground account gcp check`

`check` logs in with the key exactly like a connector does (OAuth JWT bearer). It then calls each API the examples
use, read-only, and tests the project permissions some of them need. It takes a few seconds:

```text
🔑 OAuth login of kdp-playground@my-sandbox-project.iam.gserviceaccount.com (key 3f2a91c07b4e…, from GCP_KEYFILE_CONTENT)
✅ login works
✅ Cloud Storage
✅ Pub/Sub
✅ BigQuery
✅ Spanner
✅ Bigtable
✅ Firestore
✅ Dataproc
✅ Cloud Functions
   ✅ function function-1 in europe-west2 (connect-gcp-cloud-functions-sink)
   ⚠️ no function function-11 in europe-west2, needed by fm-gcp-cloud-functions-gen2-sink unless GCP_FUNCTION_FUNCTION / GCP_FUNCTION_REGION point to another one
✅ Realtime Database
   ✅ default database https://my-sandbox-project-default-rtdb.europe-west1.firebasedatabase.app
✅ Project IAM: can grant roles (firestore sink)
✅ Service Account User: can start Dataproc clusters

🎉 project my-sandbox-project is ready for the GCP examples
```

Each failure says why and which examples it breaks:

| `check` says | Likely cause |
| --- | --- |
| `the API is not enabled 👉 gcloud services enable …` | the API is disabled on the project: run `playground account gcp setup` again, or the printed command |
| `billing is not enabled on …` | no billing account linked to the project |
| `permission denied, missing role …` | the service account lacks the role: `playground account gcp setup` grants it. Roles take up to 2 minutes to apply |
| `Google rejected the login: invalid_grant Invalid JWT Signature.` | the key was deleted or disabled: `playground account gcp setup` creates a new one |
| `Google rejected the login: invalid_grant Invalid grant: account not found` | the service account was deleted |
| `the private_key of the key file can not sign` | `GCP_KEYFILE_CONTENT` is damaged: it must be the output of `jq -aRs . keyfile.json` without the surrounding quotes |
| `GCP_PROJECT is … but the key belongs to project …` | the key comes from another project: the GCS examples create their bucket in the project of the key, the others in `GCP_PROJECT` |

Exit code 1 means the key can't log in. A failing API is only a warning: each is needed by some examples only.

To check another key, for example a `keyfile.json` left in an example folder:

```bash
playground account gcp check --keyfile connect/connect-gcp-gcs-sink/keyfile.json
```

## 🗺️ Which example needs what

| Example | Needs |
| --- | --- |
| `connect-gcp-gcs-sink` / `-source`, `fm-gcp-gcs-sink` / `-source` | Cloud Storage |
| `connect-gcp-google-pubsub-sink` / `-source`, `connect-gcp-pubsub-source`, `fm-gcp-pubsub-source` | Pub/Sub |
| `connect-gcp-bigquery-sink`, `connect-jdbc-gcp-bigquery-source`, `fm-gcp-bigquery-source`, `fm-gcp-bigquery-v2-sink` | BigQuery |
| `connect-gcp-spanner-sink`, `fm-gcp-spanner-sink`, `fm-debezium-gcp-spanner-source` | Spanner (billing) |
| `connect-gcp-bigtable-sink`, `fm-gcp-bigtable-sink` | Bigtable (billing) |
| `fm-gcp-firestore-sink` | Firestore, and the right to grant roles on the project |
| `connect-gcp-dataproc-sink` | Dataproc, Compute Engine, Cloud Storage (billing) |
| `connect-gcp-cloud-functions-sink`, `fm-gcp-cloud-functions-gen2-sink` | a function **you create** (see below) |
| `connect-gcp-firebase-sink` / `-source` | the default Realtime Database **you create** (see below) |

### ✋ What `setup` doesn't create

- **The Cloud Functions examples** call an existing function: `function-1` (self-managed) and `function-11` (fully
  managed, gen 2), both in `europe-west2`. Create it in the [Cloud Functions console](https://console.cloud.google.com/functions)
  with the default code (it answers `Hello World!`), or point the example to another one with `GCP_FUNCTION_FUNCTION` and
  `GCP_FUNCTION_REGION`. `check` lists the functions it finds.
- **The Firebase examples** write to the default Realtime Database of the project: create it in the
  [Firebase console](https://console.firebase.google.com/) (add Firebase to the project, then **Build → Realtime
  Database → Create database**, region `europe-west1`, or set `GCP_FIREBASE_REGION`). `check` shows its URL.

| Variable | Set by |
| --- | --- |
| `GCP_PROJECT`, `GCP_KEYFILE_CONTENT` | `playground account gcp setup` |
| `GCP_FUNCTION_FUNCTION`, `GCP_FUNCTION_REGION`, `GCP_FIREBASE_REGION`, `GCP_SPANNER_REGION`, `GCP_BIGTABLE_REGION`… | optional, you (`playground secrets set`), see each example's README |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--project <id>` | the project; default `GCP_PROJECT`, else the only project the account can see (with `--keyfile`: the `project_id` of the key) |
| `--keyfile <file>` | a key you were given (shared project): checked, saved and stored, nothing changed in the project, no gcloud needed |
| `--account <email>` | an account your own gcloud is logged into (`gcloud auth list`): no browser, uses your gcloud configuration |
| `--service-account <name>` | another name than `kdp-playground` |
| `--new-key` | a new key even if the saved one still works (the previous file is kept as `.bak`) |
| `--no-store` | print the export commands instead of storing the values (a throwaway project for a repro) |
| `--dry-run` | only print the APIs, the service account and the roles |

`playground account gcp check` takes `--project` and `--keyfile`.

## 💡 Good to know

- **A `keyfile.json` in an example folder wins** over `GCP_KEYFILE_CONTENT`. `setup` lists the ones holding another
  key and offers to remove them (or prints the `rm` command).
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)); the key file stays in `~/.config/kafka-docker-playground/`, outside the
  repository. When `secrets.github-repo` is configured (maintainers), it also pushes them to the GitHub Actions
  secrets of that repository: use `--no-store` to try `setup` on another project without changing CI.
- **10 keys per service account at most.** Each `setup` run from a machine without the saved key file creates one.
  `setup` warns from 8 keys; delete the old ones with
  `gcloud iam service-accounts keys list --iam-account kdp-playground@<project>.iam.gserviceaccount.com` and
  `gcloud iam service-accounts keys delete <key id> --iam-account …`.
- **Costs:** the examples delete what they create, but a run stopped halfway can leave a bucket, a Spanner instance,
  a Bigtable instance or a Dataproc cluster behind. `playground cloud-resources cleanup --resource gcp --dry-run` lists
  the ones named after you, and `playground cloud-resources nightly-cleanup enable --resource gcp` sweeps them every
  night (it reads the `GCP_PROJECT` and `GCP_KEYFILE_CONTENT` that `setup` stores).

## 🧠 CLI reference

[playground account gcp setup](/playground%20account%20gcp%20setup) · [playground account gcp check](/playground%20account%20gcp%20check) ·
[playground secrets set](/playground%20secrets%20set) · [playground secrets check](/playground%20secrets%20check)
