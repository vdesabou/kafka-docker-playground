# ☁️ Databricks examples: set up a workspace

The Databricks examples run against a **Databricks workspace on AWS**:

- self-managed: `connect/connect-databricks-delta-lake-sink`, `connect/connect-jdbc-databricks-sink`,
  `connect/connect-jdbc-databricks-source`;
- fully managed: `ccloud/fm-databricks-delta-lake-sink`.

They need a **SQL warehouse** (its host and HTTP path), a **personal access token**, and for the Delta Lake sink an
**S3 staging bucket** with AWS keys allowed on it, plus a few Unity Catalog grants. Each example creates its own table
(`pageviews_<user>_…`) and drops it at the end.

`playground account databricks setup` validates the token, takes the host and the HTTP path from the warehouse you
pick, validates the staging bucket, and stores everything. `playground account databricks check` tells you, in a few
seconds, whether it all still works.

?> **TL;DR**: create a workspace (a trial works) with a SQL warehouse, a personal access token, an S3 bucket in the
same region and an access key allowed on it, run `playground account databricks setup`, run the grants it prints.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| A **Databricks workspace on AWS** with a **SQL warehouse** | the examples run their SQL and the connector writes through it | a trial works; SQL Warehouses → a 2X-Small (serverless) with auto stop |
| A **personal access token** | the examples and the connector log in with it | Settings → Developer → Access tokens |
| An **S3 bucket** and an **access key** allowed on it | the Delta Lake sink stages its files there, then `COPY INTO` the table | any bucket; the region goes to `DATABRICKS_AWS_BUCKET_REGION` |
| **Grants** for the principal of the token | `CREATE TABLE` in `workspace.default`, `READ FILES` on the external location of the bucket | `setup` prints the statements |
| `curl`, `jq`; the aws CLI or Docker | REST API; the bucket check | |

## 🚀 Step by step

### 1. Run `playground account databricks setup`

```bash
playground account databricks setup --host https://dbc-1234abcd-5678.cloud.databricks.com
```

It asks for what is not stored yet (secrets without echo), then:

```text
✅ token of you@example.com works on dbc-1234abcd-5678.cloud.databricks.com
🏭 SQL warehouse Serverless Starter Warehouse (fa90395d7f4daff5, STOPPED): http path /sql/1.0/warehouses/fa90395d7f4daff5
✅ staging bucket my-staging-bucket (us-east-2) reachable with the staging keys
💾 stored DATABRICKS_SERVER_HOSTNAME, DATABRICKS_HOST, DATABRICKS_HTTP_PATH, DATABRICKS_TOKEN, DATABRICKS_AWS_BUCKET_NAME, DATABRICKS_AWS_BUCKET_REGION and DATABRICKS_AWS_STAGING_S3_*
🔏 the Delta Lake sink also needs these grants for you@example.com (run them in a SQL editor of the workspace):
   GRANT USE CATALOG ON CATALOG workspace TO `you@example.com`;
   GRANT USE SCHEMA, CREATE TABLE ON SCHEMA workspace.default TO `you@example.com`;
   GRANT READ FILES ON EXTERNAL LOCATION <the external location of s3://my-staging-bucket> TO `you@example.com`;
🩺 the workspace now:
…
🎉 the Databricks workspace is ready for the Databricks examples
```

With several warehouses, pass `--warehouse <name or id>`; with one, it is picked.

### 2. Run the grants, check, then run an example

```bash
playground account databricks check
playground run -f connect/connect-databricks-delta-lake-sink/databricks-delta-lake-sink.sh
```

## 🩺 When something stops working: `playground account databricks check`

```text
🔑 token of workspace dbc-1234abcd-5678.cloud.databricks.com
✅ token works: you@example.com (the principal the grants of the examples must target)
✅ SQL warehouse Serverless Starter Warehouse (fa90395d7f4daff5): STOPPED (the examples start it), 2X-Small, serverless, auto stop 10 min
✅ Staging bucket my-staging-bucket (us-east-2) reachable with the staging keys

🎉 the Databricks workspace is ready for the Databricks examples
```

| `check` says | Likely cause |
| --- | --- |
| `HTTP 403 Invalid access token` / `401` | invalid or expired `DATABRICKS_TOKEN`: create a new one |
| `HTTP 403` (other) | an IP access list of the workspace, or token usage restricted |
| `no workspace answers at this host` | wrong `DATABRICKS_SERVER_HOSTNAME`: the host of the workspace URL |
| `SQL warehouse …: HTTP 400 … not a valid endpoint id` | wrong `DATABRICKS_HTTP_PATH`: `setup` takes it from the warehouse |
| `Staging bucket … is not in <region>` / `does not exist` / `access denied` | fix `DATABRICKS_AWS_BUCKET_REGION`, the bucket name, or the staging keys |
| `DATABRICKS_HOST not set` | the JDBC examples read `DATABRICKS_HOST`: `setup` stores it |

`check` never starts the warehouse. When the examples start it, a workspace whose trial or plan has ended answers
`denyReason: INACTIVE`: no compute can start there any more.

## 🗺️ Which example needs what

| Example | Needs |
| --- | --- |
| `connect-databricks-delta-lake-sink`, `fm-databricks-delta-lake-sink` | everything: warehouse, token, staging bucket and keys, grants; also your own AWS credentials, to empty the bucket (see [AWS examples](/aws.md)) |
| `connect-jdbc-databricks-sink` / `-source` | `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN` |
| `fm-databricks-delta-lake-sink` | also a Confluent Cloud cluster on AWS: `playground account ccloud setup --cloud databricks` |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--host <URL or host>` | the workspace |
| `--token <token>` | the personal access token (asked for without echo when missing) |
| `--warehouse <name or id>` | the SQL warehouse; default the only one, else the stored one |
| `--bucket`, `--bucket-region` | the S3 staging bucket |
| `--staging-access-key-id`, `--staging-secret-access-key` | the AWS keys allowed on it |
| `--no-store` | print the export commands instead of storing the values |

## 💡 Good to know

- **A consumer lag of 0 does not prove success**: the Delta Lake sink commits its offsets once the files are staged,
  before `COPY INTO`. A missing grant then only shows in the **Query History** of the warehouse (and as
  `vendorCode=500051` in the connector log).
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets and variables: use `--no-store` to try another workspace without changing CI.

## ☁️ The other accounts

[Accounts of the examples](/how-to-use?id=☁️-accounts-of-the-examples): the `setup` and `check` commands of every provider, and how they behave.

## 🧠 CLI reference

[playground account databricks setup](/playground%20account%20databricks%20setup) · [playground account databricks check](/playground%20account%20databricks%20check) ·
[playground secrets set](/playground%20secrets%20set)
