# ☁️ Azure examples: set up a subscription

The Azure examples run against a **real Azure subscription**:

- self-managed: `connect/connect-azure-*` and `connect/connect-jdbc-azure-synapse-analytics-source` (Blob Storage,
  Data Lake Gen2, Cosmos DB, Event Hubs, Service Bus, Functions, Data Explorer, Cognitive Search, Synapse);
- fully managed: `ccloud/fm-azure-*`.

Every example creates its own resource group (`pg<user>…`), creates what it needs in it, and deletes it at the end.
What it needs from you is a **login** allowed to do that. Without a service principal, each run opens the browser for
`az login`.

`playground account azure setup` creates that service principal, with the right roles, and stores it: the examples
then log in with it, no browser. `playground account azure check` tells you, in a few seconds, whether the stored
service principal still works.

?> **TL;DR**: install the Azure CLI, run `playground account azure setup --subscription "<subscription name>"`, run an
example. With a Confluent account, the subscription is `COPS`.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| An **Azure subscription** for tests | the examples create resource groups in it | with a Confluent account: `COPS` |
| An account allowed to **register applications** in the tenant and with **Owner** (or User Access Administrator) on the subscription | `setup` creates an app registration, its service principal, and gives it roles | if not, ask someone who is to run `setup` and share the values, or see [Good to know](/azure?id=💡-good-to-know) |
| The **Azure CLI** (`az`) | `setup` runs it | [install](https://learn.microsoft.com/cli/azure/install-azure-cli), or `brew install azure-cli` |
| `openssl`, `curl`, `jq` | login, JSON | usually there already |

`check` needs neither az nor Docker.

## 🚀 Step by step

### 1. Run `playground account azure setup`

```bash
playground account azure setup --subscription "COPS"
```

A browser opens once: log in with your account. The command then does the rest:

```text
🌐 log into Azure in the browser, with an account allowed to create service principals and assign roles
👤 account you@example.com
🗂️ subscription COPS (4aef46e4-…), tenant 0893715b-…
🔌 the 10 resource providers of the examples are registered
🤖 creating service principal kdp-playground-you
🔑 added a client secret to kdp-playground-you, valid 1 year
🎭 roles of kdp-playground-you on the subscription checked (2 given now)
✅ service principal kdp-playground-you can log in
📅 its client secret expires on 2027-11-23: run setup again before (with --new-secret)
💾 stored AZ_CLIENT_ID, AZ_CLIENT_SECRET, AZ_TENANT_ID, AZURE_SUBSCRIPTION_NAME and AZ_USER
⏳ waiting for the 2 new roles to apply (max 180 seconds)
🩺 what the service principal can do on COPS:
…
🎉 subscription COPS is ready for the Azure examples
```

The login happens in an az configuration of its own (`~/.config/kafka-docker-playground/azure`), so your own az
login stays as it is. Already logged in with az as yourself? Pass `--current-login` to skip the browser.

#### What it configures

| In the subscription / tenant | What for |
| --- | --- |
| Resource providers `Microsoft.Storage`, `DocumentDB`, `EventHub`, `ServiceBus`, `Kusto`, `Search`, `Web`, `OperationalInsights`, `Insights`, `Sql` | a new subscription has some of them unregistered: the example then fails with `MissingSubscriptionRegistration` |
| App registration + service principal `kdp-playground-<user>` | the login of the examples (`az login --service-principal`) |
| … role **Contributor** on the subscription | create and delete the resource group of each example |
| … role **Role Based Access Control Administrator** on the subscription | the log analytics v2 and data lake examples assign roles (Monitoring Metrics Publisher, Storage Blob Data Owner) |
| A client secret valid 1 year, added with `--append` | the other secrets of the app (another machine, CI) keep working |

`playground account azure setup --dry-run` prints this list without changing anything. Running it again changes
nothing while the stored secret still logs in.

### 2. Check, then run an example

```bash
playground account azure check
playground run -f connect/connect-azure-blob-storage-sink/azure-blob-storage-sink.sh
```

## 🩺 When something stops working: `playground account azure check`

`check` logs in with `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` exactly like the examples, then checks
the subscription, the roles, the resource providers, the CI service principals when they are set, and the resource
groups your examples left behind:

```text
🔑 login of service principal 02379a58-… in tenant 0893715b-… (client credentials, like the examples)
✅ login works (object id 3b7365b0-…)
✅ Subscription COPS (4aef46e4-…, Enabled)
✅ Role Contributor (or broader) on the subscription
✅ Role Role Based Access Control Administrator (or broader) on the subscription
✅ Microsoft.Storage
…
✅ Microsoft.Sql
✅ AZURE_LOGS_CLIENT_ID / AZURE_LOGS_CLIENT_SECRET log in (CI, log analytics v2 and kusto sinks)
✅ AZURE_DATALAKE_CLIENT_ID / AZURE_DATALAKE_CLIENT_PASSWORD log in (CI, data lake gen2 sink)
✅ AZURE_COGNITIVE_APP_ID / AZURE_COGNITIVE_APP_PASSWORD log in (CI, cognitive search sink)

🎉 subscription COPS is ready for the Azure examples
```

| `check` says | Likely cause |
| --- | --- |
| `AADSTS7000215: Invalid client secret provided` | `AZ_CLIENT_SECRET` is wrong, or the secret **ID** was stored instead of its value |
| `AADSTS7000222` | the client secret has expired: `playground account azure setup --new-secret` |
| `AADSTS700016` / `AADSTS700038` | no application with this `AZ_CLIENT_ID` in tenant `AZ_TENANT_ID`: wrong tenant, or the app was deleted |
| `AADSTS53003` | blocked by a conditional access policy of the tenant |
| `the service principal has no role on it` | the service principal has no role on `AZURE_SUBSCRIPTION_NAME` |
| `Role … missing on the subscription` | `setup` grants it (your account needs Owner or User Access Administrator) |
| `Microsoft.X: NotRegistered` | `az provider register --namespace Microsoft.X`, or `setup` |
| `N resource group(s) left by your examples` | a run stopped halfway: `playground cloud-resources cleanup --resource azure --dry-run` |

Exit code 1 means the service principal can't log in (or none is stored).

## 🗺️ Which example needs what

| Example | Needs |
| --- | --- |
| blob storage sink / source, cosmosdb (v1, v2) sink / source, event hubs source, service bus source, log analytics sink, synapse sink and source, cognitive search sink (self-managed), functions sink | the login (Contributor) and their resource provider |
| `connect-azure-data-lake-storage-gen2-sink`, `fm-azure-data-lake-storage-gen2-sink` | locally: an Entra app the example creates (`pg<user>`, see below); in CI: `AZURE_DATALAKE_CLIENT_ID` / `AZURE_DATALAKE_CLIENT_PASSWORD` |
| `connect-azure-data-explorer-kusto-sink`, `fm-azure-data-explorer-kusto-sink` | locally: an Entra app the example creates; in CI: `AZURE_LOGS_CLIENT_ID` / `AZURE_LOGS_CLIENT_SECRET` |
| `fm-azure-cognitive-search-sink` | locally: a service principal the example creates; in CI: `AZURE_COGNITIVE_APP_ID` / `AZURE_COGNITIVE_APP_PASSWORD` |
| `fm-azure-log-analytics-v2-sink` | `AZURE_LOGS_CLIENT_ID`, `AZURE_LOGS_CLIENT_SECRET`, `AZURE_LOGS_SP_OBJECT_ID`, and the right to assign roles |
| `fm-azure-*` | also a Confluent Cloud cluster on Azure: `playground account ccloud setup --cloud azure` |

| Variable | Set by |
| --- | --- |
| `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET`, `AZ_TENANT_ID`, `AZURE_SUBSCRIPTION_NAME`, `AZ_USER` | `playground account azure setup` |
| `AZURE_REGION` | optional (default `westeurope`) |
| `AZURE_LOGS_*`, `AZURE_DATALAKE_*`, `AZURE_COGNITIVE_*` | CI only, set by the maintainers (`check` tests them when they are set) |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--subscription <name>` | the subscription; default `AZURE_SUBSCRIPTION_NAME`, else the only one the account can see |
| `--current-login` | the account your own az is logged into: no browser |
| `--tenant <id or domain>` | the tenant to log into, when your account belongs to several |
| `--service-principal <name>` | another name than `kdp-playground-<user>` (never `pg<user>`: the data lake example resets the secrets of that app) |
| `--new-secret` | add a new client secret even if the stored one still works |
| `--no-store` | print the export commands instead of storing the values |
| `--dry-run` | only print the providers, the service principal and the roles |

## 💡 Good to know

- **With the service principal, the examples that create Entra apps locally** (data lake gen2, kusto, cognitive
  search, log analytics v2) run `az ad app create` as the service principal, which needs the Graph permission
  `Application.ReadWrite.OwnedBy` (admin consent). Without it, run these few examples logged in as yourself: unset
  `AZ_CLIENT_ID` for that run.
- **The secret expires after 1 year.** `setup` prints the date; `check` reports `AADSTS7000222` once it has expired.
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets and variables of that repository, so **CI switches to your service principal**: use
  `--no-store` to try `setup` without changing CI.
- **`AZ_USER`** is the `owner_email` tag of the resource groups: `setup` stores your email, otherwise a service
  principal login would tag them with its app id.
- **Role assignments and provider registrations take a few minutes to apply**: `setup` waits for the roles, `check`
  shows `Registering` for a provider still on its way.

## ☁️ The other accounts

[Accounts of the examples](/accounts.md): the `setup` and `check` commands of every provider, and how they behave.

## 🧠 CLI reference

[playground account azure setup](/playground%20account%20azure%20setup) · [playground account azure check](/playground%20account%20azure%20check) ·
[playground secrets set](/playground%20secrets%20set)
