# ☁️ Accounts of the examples

Many examples run against a real third-party account: a Salesforce org, a Google Cloud project, an Azure
subscription, a Snowflake account, AWS keys, a ServiceNow instance, a Databricks workspace, SaaS accounts (Zendesk,
Jira, Marketo, ClickHouse Cloud, Couchbase Capella, MongoDB Atlas, PagerDuty), and your Confluent Cloud clusters for
the fully managed examples. Setting these accounts up by hand (apps, service accounts, roles, keys,
the exact format of each variable) is the longest part of a first run, and a mistake only shows up minutes into it.

`playground account` does that part for you, with the same two commands for every provider:

```bash
playground account <provider> setup      # configure the account once, store the variables
playground account <provider> check      # a few seconds: does the stored login still work, what is missing
```

?> **TL;DR**: before the first run of an example that needs an account, run `playground account <provider> setup`.
When an example fails on a login, a permission or a missing resource, run `playground account <provider> check`
first: it says why, and which examples it breaks.

## 🗺️ Providers

| Provider | Examples | What `setup` does | What `check` verifies | Stays manual | Guide |
| --- | --- | --- | --- | --- | --- |
| `ccloud` | `ccloud/fm-*` | creates your environment `pg-<user>`, one Basic cluster per cloud, their API keys | the environment, each cluster (exists, UP, cloud and region), each API key (exists, belongs to the cluster, lists topics / subjects), free schemas limit, exported variables that hide the profile | being logged in with the confluent CLI | [Confluent Cloud examples](/how-to-use?id=🏗️-recommended-your-own-clusters-and-a-nightly-cleanup) |
| `salesforce` | `connect-salesforce-*`, `fm-salesforce-*` | deploys an External Client App (JWT bearer), a Platform Event and Change Data Capture on Contact | the JWT login like a connector, Platform Event, CDC | signing up for the org, storing the password and security token | [Salesforce examples](/salesforce.md) |
| `gcp` | `connect-gcp-*`, `fm-gcp-*` | enables the APIs, creates a service account with its roles and a key (or `--keyfile` for a key you were given) | the key, each API, billing, missing roles, the Cloud Function and the Realtime Database | creating the project with billing | [GCP examples](/gcp.md) |
| `azure` | `connect-azure-*`, `fm-azure-*` | creates a service principal with its roles and a client secret, registers the resource providers | the login (AADSTS errors), roles, resource providers, leftover resource groups | — | [Azure examples](/azure.md) |
| `snowflake` | `connect-snowflake-sink`, `connect-jdbc-snowflake-*`, `fm-snowflake-*` | turns the account URL into the identifier the examples use, validates the admin login | the login (wrong password, MFA, locked user), roles, default role, edition | signing up for the account | [Snowflake examples](/snowflake.md) |
| `aws` | `connect-aws-*`, `connect-jdbc-aws-*`, `fm-aws-*` | validates the access keys and the region; `--assume-role` creates the IAM role of the assume-role variants | the keys, temporary credentials, region, one probe per service, bucket name, assume role | creating the IAM user and its access key | [AWS examples](/aws.md) |
| `servicenow` | `connect-servicenow-*`, `fm-servicenow-*` | normalizes the URL, wakes the instance up, fixes basic authentication for admin | awake, hibernating, released, 401, the tables | requesting the developer instance | [ServiceNow examples](/servicenow.md) |
| `databricks` | `connect-databricks-delta-lake-sink`, `connect-jdbc-databricks-*`, `fm-databricks-delta-lake-sink` | takes the HTTP path and host from the SQL warehouse, validates the token and the S3 staging bucket, prints the grants | the token, the warehouse, the staging bucket | creating the workspace, running the grants | [Databricks examples](/databricks.md) |

| `zendesk`, `jira`, `marketo`, `clickhouse`, `couchbase`, `mongodb-atlas`, `pagerduty` | see [below](/accounts?id=🧾-the-saas-accounts) | asks for the 3 values, puts them in the right form, validates them, stores them | one or two calls: login, and what expires, pauses or idles | signing up | [The SaaS accounts](/accounts?id=🧾-the-saas-accounts) |

Each guide has the same sections: what you need, step by step, the `check` output with the likely cause of each
failure, which example needs what, options, good to know.

## 🧾 The SaaS accounts

These accounts have nothing to configure: the examples only need 3 values (URL or host, user, password or token).
What goes wrong is rarely a typo: they are **trial or free accounts that expire, pause or go idle**, and the
connector then fails minutes into the run. `setup` asks for the values (secrets without echo), puts them in the form
the examples use, validates them and stores them; `check` names the case in a few seconds.

```bash
playground account jira setup          # or: JIRA_URL=… JIRA_USERNAME=… JIRA_API_TOKEN=… playground account jira setup
playground account jira check
```

| Provider | Examples | Variables | `check` | Failure modes it names |
| --- | --- | --- | --- | --- |
| `zendesk` | `connect-zendesk-source`, `fm-zendesk-source` | `ZENDESK_URL`, `ZENDESK_USERNAME` (`<email>/token`), `ZENDESK_PASSWORD` (API token) | `users/me`, `tickets` | wrong token, `/token` suffix missing, API token access disabled, trial ended (14 days) |
| `jira` | `connect-jira-source`, `fm-jira-source` | `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN` | `myself`, project search | token expired (Atlassian API tokens expire), wrong site, no project visible |
| `marketo` | `connect-marketo-source`, `fm-marketo-sink` | `MARKETO_ENDPOINT_URL` (without `/rest`), `MARKETO_CLIENT_ID`, `MARKETO_CLIENT_SECRET` | OAuth token, `leads/describe` | wrong client, `603` (the API role of the LaunchPoint service), sandbox expired |
| `clickhouse` | `connect-clickhouse-sink`, `fm-clickhouse-sink` | `CLICKHOUSE_CLOUD_HOSTNAME`, `_USERNAME`, `_PASSWORD` | `SELECT version()` over HTTPS | authentication failed, service stopped or deleted (trial ended), IP access list; an **idle** service is woken up by the query |
| `couchbase` | `fm-couchbase-sink`, `fm-couchbase-source` | `COUCHBASE_HOSTNAME`, `_USERNAME`, `_PASSWORD`, optional `COUCHBASE_CAPELLA_API_KEY` / `_ORG_ID` / `_PROJECT_ID` / `_CLUSTER_ID` | Capella API: cluster state, allowed IPs | cluster **turned off** (free tier, after 72 hours without use: `setup` turns it back on), API key expired, allowed IPs |
| `mongodb-atlas` | `fm-mongodb-atlas-sink`, `fm-mongodb-atlas-source` | `MONGODB_ATLAS_HOST` (without `mongodb+srv://`), `_USER`, `_PASSWORD` | SRV record, `mongosh` ping (mongo image) | wrong host, authentication failed, cluster **paused** (M0, after 60 days without connections), IP access list |
| `pagerduty` | `connect-pagerduty-sink` | `PAGERDUTY_API_KEY`, `PAGERDUTY_SERVICE_ID`, `PAGERDUTY_USER_EMAIL` | the service, the user | key revoked, service deleted, email not a user of the account |

The fully managed connectors connect from Confluent Cloud IPs: ClickHouse, Couchbase and MongoDB Atlas must allow
them (or `0.0.0.0/0`); `check` reminds it, and shows the allowed IPs of a Capella cluster.

## ⚙️ How they behave

Every `setup` and `check` follows the same rules:

| | `setup` | `check` |
| --- | --- | --- |
| **Changes** | configures the account, then stores the variables with [playground secrets set](/playground%20secrets%20set) | nothing: read-only |
| **Run twice** | changes nothing: existing apps, service accounts, roles and keys are reused while they still work | same answer |
| **Logins** | one browser login at most, in a configuration of its own (your own gcloud / az login is left alone), or the login you already have (`--account`, `--current-login`, `--target-org`) | the stored credentials, exactly like the examples use them |
| **Tools** | the provider's CLI when it needs one (`sf`, `gcloud` or its Docker image, `az`, `aws` or its Docker image); none for the others (the `mongo` image for MongoDB Atlas) | `curl`, `jq`, `openssl` (the `aws` CLI or its image for AWS) |
| **Ends with** | a `check`, waiting for the new roles to apply | one line per item, ✅ / ⚠️ / ❌, each failure with its likely cause and the examples it breaks |
| **Exit code** | 1 when nothing could be stored | 1 when the login fails; a missing item that only some examples need is a warning |

Common flags of `setup`: `--no-store` prints the `export` commands instead of storing (a throwaway account, a test),
and `--dry-run`, where it exists, prints what would be created.

## 🔐 Where the values go

`setup` stores the variables in your secrets store (macOS Keychain, 1Password, Vault…, see
[Credentials and the 1Password setup](/deep-dive-secrets.md)), never in the repository, and `playground run` loads,
for each example, the ones it needs. Keys and certificates that must be files (the Salesforce keystore, the GCP key)
are kept in `~/.config/kafka-docker-playground/`.


## 🩺 When an example fails

`playground run` already runs the `check` of the example's provider before stopping or starting anything (a few
seconds). If the login fails, the run stops right there, with the `setup` command to fix it; an item only some
examples need is shown and the run goes on. Not in CI; to turn it off: `playground config account-check-before-run false`.

Otherwise, or for a closer look:

1. `playground account <provider> check`: a login refused, a role missing, an API disabled, an instance hibernating…
2. `playground secrets check -f <example>`: which variables the example needs, and where each one comes from (or
   that it is missing).
3. The guide of the provider: the table of `check` messages and their likely causes.

## 🧠 CLI reference

[playground account](/playground%20account) · [playground secrets](/playground%20secrets) ·
[Which command do I need?](/which-command.md)
