# ❄️ Snowflake examples: set up an account

The Snowflake examples run against a **real Snowflake account**:

- self-managed: `connect/connect-snowflake-sink` (Snowpipe, Snowpipe Streaming, Iceberg), `connect/connect-jdbc-snowflake-sink`,
  `connect/connect-jdbc-snowflake-source`;
- fully managed: `ccloud/fm-snowflake-sink` (and its Iceberg variants), `ccloud/fm-snowflake-source`.

Each script logs in with an **admin user and its password** (with `snowsql`), then creates its own database, role,
warehouse and user (named `PG…<user>…`), the connector logging in with a key pair. What they need from you is that
admin login, with the account identifier in the right form and the right roles.

`playground account snowflake setup` validates the login and stores it. `playground account snowflake check` tells
you, in a few seconds, whether the stored login still works and has what the examples need.

?> **TL;DR**: sign up for a [30-day trial](https://signup.snowflake.com/) (pick **Enterprise** for the Iceberg
variants), run `playground account snowflake setup` and paste the account URL, the user and the password, run an
example.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| A **Snowflake account** | the examples create databases, roles, warehouses and users in it | a [30-day trial](https://signup.snowflake.com/) works; **Enterprise** edition for the Iceberg variants |
| An **admin user** with a password, able to use `SECURITYADMIN`, `SYSADMIN`, `USERADMIN` (and `ACCOUNTADMIN` for Iceberg), default role `ACCOUNTADMIN` | the scripts create their objects with these roles, the database with the default role | the user of a trial has all of them |
| `curl`, `jq` | login, JSON | usually there already |

Neither `setup` nor `check` needs snowsql or Docker.

## 🚀 Step by step

### 1. Sign up

Sign up at [signup.snowflake.com](https://signup.snowflake.com/), pick **Enterprise** if you plan to run the Iceberg
variants, any cloud and region. Activate the account from the email and set the user and password.

### 2. Run `playground account snowflake setup`

```bash
playground account snowflake setup
```

It asks for what is not stored yet: the **account URL** (Snowsight → your name → **Account** → copy the account URL,
or any form of the identifier), the user and the password (without echo):

```text
🏔️ account identifier or URL (Snowsight > your name > Account > copy the account URL): https://xy12345.eu-west-3.aws.snowflakecomputing.com
👤 admin user: ADMIN
🔐 password of ADMIN:
🏔️ account identifier: xy12345.eu-west-3.aws (from https://xy12345.eu-west-3.aws.snowflakecomputing.com)
✅ ADMIN can log into xy12345.eu-west-3.aws
💾 stored SNOWFLAKE_ACCOUNT_NAME, SNOWFLAKE_USERNAME and SNOWFLAKE_PASSWORD
🩺 what this login can do:
…
🎉 the Snowflake account is ready for the Snowflake examples
```

The examples build `https://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com`: `setup` strips `https://`,
`.snowflakecomputing.com` and the path, so both `<locator>.<region>.<cloud>` and `orgname-accountname` work. A login
that fails stores nothing.

### 3. Check, then run an example

```bash
playground account snowflake check
playground run -f connect/connect-snowflake-sink/snowflake-sink.sh
```

## 🩺 When something stops working: `playground account snowflake check`

`check` logs in exactly like the examples (password login, the same endpoint snowsql uses), then checks the roles,
the default role, the edition and the warehouses the examples left behind:

```text
🔑 password login of ADMIN on xy12345.eu-west-3.aws.snowflakecomputing.com (like snowsql in the examples)
✅ login works
✅ Account myorg-myaccount (region AWS_EU_WEST_3, Snowflake 10.42.104)
✅ Role SECURITYADMIN
✅ Role SYSADMIN
✅ Role USERADMIN
✅ Role ACCOUNTADMIN
✅ Default role ACCOUNTADMIN
⚠️ Edition unknown (only ORGADMIN sees it): the Iceberg variants need Enterprise
ℹ️  10 warehouse(s) PGWH… left by the examples, 0 running (they suspend themselves; drop them with DROP WAREHOUSE)

🎉 the Snowflake account is ready for the Snowflake examples
```

| `check` says | Likely cause |
| --- | --- |
| `390100 Incorrect username or password was specified` | wrong `SNOWFLAKE_USERNAME` or `SNOWFLAKE_PASSWORD` |
| `no Snowflake account answers at …` | wrong `SNOWFLAKE_ACCOUNT_NAME`: use the account URL without `https://` and `.snowflakecomputing.com` |
| `… MFA …` | Snowflake requires MFA for this user, and the examples log in with a password only: use a user without MFA enforcement (see [Good to know](/snowflake?id=💡-good-to-know)) |
| `the user is temporarily locked` | too many failed logins: wait 15 minutes |
| `a network policy blocks this IP address` | a network policy of the account |
| `Role X: … can't use it` | `GRANT ROLE X TO USER <user>` as ACCOUNTADMIN |
| `Default role …` | the scripts create their database with the default role: `ALTER USER <user> SET DEFAULT_ROLE = ACCOUNTADMIN` |
| `Edition STANDARD` | the Iceberg variants need Enterprise |

Exit code 1 means the login fails.

## 🗺️ Which example needs what

| Example | Needs |
| --- | --- |
| `snowflake-sink.sh`, `-proxy.sh`, `-snowpipe-streaming.sh`, `jdbc-snowflake-sink.sh`, `jdbc-snowflake-source.sh`, `fully-managed-snowflake-sink.sh`, `fully-managed-snowflake-source.sh` | the login, `SECURITYADMIN`, `SYSADMIN`, `USERADMIN` |
| `snowflake-sink-snowpipe-streaming-iceberg.sh`, `fully-managed-snowflake-iceberg-sink.sh` | also `ACCOUNTADMIN` and **Enterprise** |
| `snowflake-sink-snowpipe-streaming-iceberg-ext-volume.sh`, `fully-managed-snowflake-iceberg-ext-volume-sink.sh` | also `ACCOUNTADMIN` as **default role**, Enterprise, and AWS credentials (an S3 bucket and an IAM role, see [AWS examples](/aws.md)) |
| `ccloud/fm-snowflake-*` | also a Confluent Cloud cluster: `playground account ccloud setup` |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--account <identifier or URL>` | the account, in any form |
| `--user <user>` | the admin user |
| `--password <password>` | its password (asked for without echo when missing; a flag value stays in your shell history) |
| `--no-store` | print the export commands instead of storing the values |

## 💡 Good to know

- **MFA:** Snowflake is rolling out mandatory MFA for password logins of human users. The examples log in with
  `snowsql` and a password, so if `check` reports MFA, use an admin user that is not subject to it (for example
  `TYPE = LEGACY_SERVICE`, which Snowflake is also phasing out), or ask your Snowflake admin for an exception. Moving
  the examples to a key-pair service user is the long-term fix.
- **The objects the examples create are not deleted** (database, role, warehouse, user `PG…<user>…`): each run drops
  and recreates its own. The warehouses suspend themselves; `check` counts them.
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets and variables: use `--no-store` to try another account without changing CI.

## ☁️ The other accounts

[Accounts of the examples](/how-to-use?id=☁️-accounts-of-the-examples): the `setup` and `check` commands of every provider, and how they behave.

## 🧠 CLI reference

[playground account snowflake setup](/playground%20account%20snowflake%20setup) · [playground account snowflake check](/playground%20account%20snowflake%20check) ·
[playground secrets set](/playground%20secrets%20set)
