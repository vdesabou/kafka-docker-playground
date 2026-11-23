# ☁️ Accounts of the examples

Many examples run against a real third-party account: a Salesforce org, a Google Cloud project, an Azure
subscription, a Snowflake account, AWS keys, a ServiceNow instance, a Databricks workspace, and your Confluent Cloud
clusters for the fully managed examples. Setting these accounts up by hand (apps, service accounts, roles, keys,
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
| `ccloud` | `ccloud/fm-*` | creates your environment `pg-<user>`, one Basic cluster per cloud, their API keys | — (`playground cloud-resources ccloud list`) | being logged in with the confluent CLI | [Confluent Cloud examples](/how-to-use?id=🏗️-recommended-your-own-clusters-and-a-nightly-cleanup) |
| `salesforce` | `connect-salesforce-*`, `fm-salesforce-*` | deploys an External Client App (JWT bearer), a Platform Event and Change Data Capture on Contact | the JWT login like a connector, Platform Event, CDC | signing up for the org, storing the password and security token | [Salesforce examples](/salesforce.md) |
| `gcp` | `connect-gcp-*`, `fm-gcp-*` | enables the APIs, creates a service account with its roles and a key (or `--keyfile` for a key you were given) | the key, each API, billing, missing roles, the Cloud Function and the Realtime Database | creating the project with billing | [GCP examples](/gcp.md) |
| `azure` | `connect-azure-*`, `fm-azure-*` | creates a service principal with its roles and a client secret, registers the resource providers | the login (AADSTS errors), roles, resource providers, leftover resource groups | — | [Azure examples](/azure.md) |
| `snowflake` | `connect-snowflake-sink`, `connect-jdbc-snowflake-*`, `fm-snowflake-*` | turns the account URL into the identifier the examples use, validates the admin login | the login (wrong password, MFA, locked user), roles, default role, edition | signing up for the account | [Snowflake examples](/snowflake.md) |
| `aws` | `connect-aws-*`, `connect-jdbc-aws-*`, `fm-aws-*` | validates the access keys and the region; `--assume-role` creates the IAM role of the assume-role variants | the keys, temporary credentials, region, one probe per service, bucket name, assume role | creating the IAM user and its access key | [AWS examples](/aws.md) |
| `servicenow` | `connect-servicenow-*`, `fm-servicenow-*` | normalizes the URL, wakes the instance up, fixes basic authentication for admin | awake, hibernating, released, 401, the tables | requesting the developer instance | [ServiceNow examples](/servicenow.md) |
| `databricks` | `connect-databricks-delta-lake-sink`, `connect-jdbc-databricks-*`, `fm-databricks-delta-lake-sink` | takes the HTTP path and host from the SQL warehouse, validates the token and the S3 staging bucket, prints the grants | the token, the warehouse, the staging bucket | creating the workspace, running the grants | [Databricks examples](/databricks.md) |

Each guide has the same sections: what you need, step by step, the `check` output with the likely cause of each
failure, which example needs what, options, good to know.

## ⚙️ How they behave

Every `setup` and `check` follows the same rules:

| | `setup` | `check` |
| --- | --- | --- |
| **Changes** | configures the account, then stores the variables with [playground secrets set](/playground%20secrets%20set) | nothing: read-only |
| **Run twice** | changes nothing: existing apps, service accounts, roles and keys are reused while they still work | same answer |
| **Logins** | one browser login at most, in a configuration of its own (your own gcloud / az login is left alone), or the login you already have (`--account`, `--current-login`, `--target-org`) | the stored credentials, exactly like the examples use them |
| **Tools** | the provider's CLI when it needs one (`sf`, `gcloud` or its Docker image, `az`, `aws` or its Docker image); none for Snowflake, ServiceNow, Databricks | `curl`, `jq`, `openssl` (the `aws` CLI or its image for AWS) |
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

1. `playground account <provider> check`: a login refused, a role missing, an API disabled, an instance hibernating…
2. `playground secrets check -f <example>`: which variables the example needs, and where each one comes from (or
   that it is missing).
3. The guide of the provider: the table of `check` messages and their likely causes.

## 🧠 CLI reference

[playground account](/playground%20account) · [playground secrets](/playground%20secrets) ·
[Which command do I need?](/which-command.md)
