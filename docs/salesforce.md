# ☁️ Salesforce examples: set up an org

The Salesforce examples run against a **real Salesforce org**:

- self-managed: `connect/connect-salesforce-*` (CDC, Platform Events, PushTopics, Bulk API, SObject sink);
- fully managed: `ccloud/fm-salesforce-*`.

The org needs a few things the connectors rely on: an External Client App for the OAuth JWT Bearer flow, a Platform
Event, and Change Data Capture on `Contact`. The examples also read your credentials from environment variables.

`playground salesforce setup` configures an org in one command. Only signing up for the org stays manual.
`playground salesforce check` tells you, in a few seconds, whether the stored credentials still work.

?> **TL;DR**: sign up for a free Developer Edition org, install the Salesforce CLI
(`npm install --global @salesforce/cli`), run `playground salesforce setup`, store your password and security token
with `playground secrets set`, run an example.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| A **Salesforce Developer Edition org** | the examples create and read Contacts, events, PushTopics, Bulk API jobs in it | free signup, see [step 1](/salesforce?id=_1-sign-up-for-a-developer-edition-org) |
| The **Salesforce CLI** (`sf`) on your machine | `setup` deploys the metadata with it, and `sf org login web` uses your browser | see [step 2](/salesforce?id=_2-install-the-salesforce-cli) |
| `openssl`, `curl`, `jq` | key pair, JWT login, JSON | usually there already (`brew install jq` on macOS) |
| A browser on the same machine | the one-time login of `setup` | or log in beforehand and pass `--target-org` (see [Options](/salesforce?id=⚙️-options)) |

Docker is **not** needed for `setup` and `check`, only to run the examples.

## 🚀 Step by step

### 1. Sign up for a Developer Edition org

Sign up at [developer.salesforce.com/signup](https://developer.salesforce.com/signup), confirm the email, and set
the password. A Developer Edition org is free and doesn't expire as long as you log in now and then.

?> The **sink** examples (Bulk API sink, SObject sink, self-managed and fully managed) read from a first org and
write to a **second** one: sign up twice if you plan to run them (see [Which org for which example](/salesforce?id=🗺️-which-org-for-which-example)).

### 2. Install the Salesforce CLI

The Salesforce CLI is a Node.js application. With Node.js (LTS or later) installed:

```bash
npm install --global @salesforce/cli
sf --version          # @salesforce/cli/2.x
```

Other ways (macOS and Windows installers, Linux tarballs) are on the
[Salesforce CLI page](https://developer.salesforce.com/tools/salesforcecli). `setup` stops with this message when `sf`
is missing:

```text
❌ the Salesforce CLI (sf) is not installed
   install it with: npm install --global @salesforce/cli (or see https://developer.salesforce.com/tools/salesforcecli)
```

!> You need `sf` (version 2). The old `sfdx` CLI, and the `sfdx-cli` container the examples use to create test
records, are too old for the External Client App metadata that `setup` deploys.

To update it later: `npm update --global @salesforce/cli` (or `sf update` with the installers).

### 3. Run `playground salesforce setup`

```bash
playground salesforce setup
```

A browser opens once: log into your new org and click **Allow**. The command then does the rest, in about 30 seconds
on a fresh org:

```text
🌐 log into your Salesforce org in the browser that opens (https://login.salesforce.com), then click Allow
☁️ org 00D…, user you@example.com
👤 the External Client App is pre-authorized for profile "System Administrator"
🚀 deploying External Client App kdp_jwt, MyPlatformEvent__e and Change Data Capture on Contact
🚀 deploying the policies of kdp_jwt (pre-authorized for "System Administrator", IP restrictions relaxed)
🔑 consumer key of kdp_jwt: 3MVG9lsAlIP.…
⏳ waiting for the JWT bearer login of you@example.com to work (a new External Client App takes 2 to 10 minutes to be active, max 600 seconds)
✅ JWT bearer login works for you@example.com
💾 stored SALESFORCE_USERNAME, SALESFORCE_INSTANCE and SALESFORCE_CONSUMER_KEY_WITH_JWT
✋ Salesforce can't give these two back, store them yourself if not done yet:
   playground secrets set SALESFORCE_PASSWORD
   playground secrets set SALESFORCE_SECURITY_TOKEN      (emailed by Salesforce: Settings > My Personal Information > Reset My Security Token)
🩺 check it any time with: playground salesforce check
```

What it configures in the org:

| In the org | What for |
| --- | --- |
| External Client App `kdp_jwt` with the OAuth **JWT Bearer** flow and the certificate of your keystore | the connectors log in with `salesforce.grant.type=JWT_BEARER`, the examples create test records with the same login |
| … **pre-authorized** for the profile of your user, **IP restrictions relaxed** | no browser approval; fully managed connectors log in from Confluent Cloud IPs |
| Platform Event `MyPlatformEvent__e`, text field `Message__c` | Platform Events source and sink examples |
| Change Data Capture on `Contact` | CDC source examples |

Running it again on the same org changes nothing.

### 4. Store the password and the security token

Salesforce can't give these two back through an API, so store them yourself, once:

```bash
playground secrets set SALESFORCE_PASSWORD
playground secrets set SALESFORCE_SECURITY_TOKEN
```

The security token comes by email. To get a new one: avatar → **Settings** → **My Personal Information** →
**Reset My Security Token**. Changing the password also resets it.

?> The JWT examples (CDC, Platform Events, PushTopics, and the Bulk API versions that support `JWT_BEARER`) don't
log in with them, but the examples check that they are set. Older connector versions still log in with the password
and the token.

### 5. Check, then run an example

```bash
playground salesforce check
playground run -f connect/connect-salesforce-cdc-source/salesforce-cdc-source.sh
```

## 🩺 When something stops working: `playground salesforce check`

`check` logs in exactly like a connector does (JWT Bearer, with the stored `SALESFORCE_USERNAME`,
`SALESFORCE_CONSUMER_KEY_WITH_JWT`, `SALESFORCE_INSTANCE` and your keystore). It needs neither Docker nor `sf`, and
takes a few seconds:

```text
🔑 JWT bearer login of you@example.com on https://login.salesforce.com (SALESFORCE_CONSUMER_KEY_WITH_JWT 3MVG9lsAlIP.…, certificate of …/salesforce-confluent.keystore.jks)
✅ JWT bearer login works (https://your-domain.my.salesforce.com)
✅ Platform Event MyPlatformEvent__e exists
✅ Change Data Capture is enabled on Contact (entities: ContactChangeEvent)
🎉 the org is ready for all the Salesforce examples
```

When Salesforce rejects the login, it prints the reason and the likely cause:

| Salesforce says | Likely cause |
| --- | --- |
| `client identifier invalid` | `SALESFORCE_CONSUMER_KEY_WITH_JWT` is not the consumer key of an External Client App of this org, or the app was created less than 10 minutes ago |
| `user hasn't approved this consumer` | the app is not pre-authorized for this user: its OAuth policy must be *Admin approved users are pre-authorized* and list the user's profile (`setup` does it) |
| `invalid assertion` / `invalid signature` | the certificate of the app does not match the private key of your keystore |
| `audience is invalid` | wrong `SALESFORCE_INSTANCE`: `https://login.salesforce.com`, or `https://test.salesforce.com` for a sandbox or a scratch org |
| `user hasn't been …`, or the user is inactive, locked or its password expired | the user can't log in: check it in **Setup → Users** |

Salesforce also shows the reason of every login attempt in **Setup → Login History**.

A missing Platform Event or CDC is only a warning: each is needed by some examples only. Exit code 1 means the login
failed.

## 🗺️ Which org for which example

| Example | Org | Needs |
| --- | --- | --- |
| `connect-salesforce-cdc-source`, `fm-salesforce-cdc-source` | #1 | CDC on `Contact` |
| `connect-salesforce-platform-events-source` / `-sink`, `fm-salesforce-platform-events-source` / `-sink` | #1 | `MyPlatformEvent__e` |
| `connect-salesforce-pushtopics-source`, `fm-salesforce-pushtopics-source` | #1 | (PushTopic created by the example) |
| `connect-salesforce-bulkapi-source`, `fm-salesforce-bulkapi-2-0-source`, `fm-salesforce-v2-source` | #1 | |
| `fm-salesforce-bulkapi-source` | #1 | also the username-password OAuth flow: `SALESFORCE_CONSUMER_KEY` / `SALESFORCE_CONSUMER_PASSWORD` of a Connected App, set up by hand (see its README); blocked by default on new orgs |
| `connect-salesforce-bulkapi-sink`, `connect-salesforce-sobject-sink`, `fm-salesforce-bulkapi-2-0-sink`, `fm-salesforce-sobject-sink` | #1 (source) **and #2** (sink) | `playground salesforce setup --account2` on the second org |

For the second org:

```bash
playground salesforce setup --account2            # stores SALESFORCE_USERNAME_ACCOUNT2, …_INSTANCE_ACCOUNT2, …_CONSUMER_KEY_WITH_JWT_ACCOUNT2
playground secrets set SALESFORCE_PASSWORD_ACCOUNT2
playground secrets set SALESFORCE_SECURITY_TOKEN_ACCOUNT2
playground salesforce check --account2
```

| Variable | Set by |
| --- | --- |
| `SALESFORCE_USERNAME`, `SALESFORCE_INSTANCE`, `SALESFORCE_CONSUMER_KEY_WITH_JWT` (`_ACCOUNT2`) | `playground salesforce setup` (`--account2`) |
| `SALESFORCE_PASSWORD`, `SALESFORCE_SECURITY_TOKEN` (`_ACCOUNT2`) | you, with `playground secrets set` |

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--account2` | the second org of the sink examples (`SALESFORCE_*_ACCOUNT2`) |
| `--target-org <alias>` | an org the `sf` CLI is already logged into: no browser (e.g. on a remote machine, log in first with `sf org login web --alias my-org` where a browser is available, or `sf org login sfdx-url`) |
| `--instance-url https://test.salesforce.com` | a sandbox or a scratch org |
| `--suffix KDP_CDC` | per-test variables (`SALESFORCE_USERNAME_KDP_CDC`…), read by the examples before the shared ones |
| `--no-store` | print the values instead of storing them (a throwaway org for a repro) |
| `--dry-run` | only render the metadata in `/tmp/playground-salesforce-setup`, deploy nothing |
| `--app-name <name>` | another name than `kdp_jwt` for the External Client App |
| `--keystore <file>` / `--generate-keystore` | import a keystore / replace yours with a new key pair (see below) |
| `--max-wait <seconds>` | how long to wait for the new app to accept JWT logins (default 600) |

`playground salesforce check` takes `--account2`, `--suffix` and `--keystore` too.

## 🔐 The keystore (JWT key pair)

The JWT Bearer flow signs the login with a private key; the External Client App holds the matching certificate.

- **Where it lives:** `~/.config/kafka-docker-playground/salesforce-confluent.keystore.jks` (PKCS12, password
  `confluent`), outside the repository. The examples copy it into their folder, where the connector reads it.
- **The first time:** `setup` reuses a `salesforce-confluent.keystore.jks` already present in an example folder, so
  the orgs that trust it keep working. Otherwise it generates a key pair. The private key never leaves your machine.
- **`--generate-keystore`** replaces it; the previous one is kept as `.bak`. Every org set up with the previous one
  must then be set up again (run `setup` on it).
- **Without your keystore,** the examples try to download the shared one from the playground S3 bucket. That only
  works for Confluent employees with AWS credentials set.

## 💡 Good to know

- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets of that repository: use `--no-store` to try `setup` on another org without changing CI.
- **Change Data Capture limit:** a Developer Edition org allows 5 CDC entities. If the deploy fails on CDC, unselect
  one in **Setup → Change Data Capture**.
- **A new app takes 2 to 10 minutes** to accept JWT logins: `setup` waits for it (up to `--max-wait`). A
  `client identifier invalid` from `check` right after a manual change is often just that.
- **Sandbox and scratch orgs** log in with the audience `https://test.salesforce.com`: pass
  `--instance-url https://test.salesforce.com` to `setup`, it stores it as `SALESFORCE_INSTANCE`. A scratch org user has
  no password: `sf org generate password --target-org <alias>` creates one.
- **Org deactivated, locked or expired?** Sign up for a new one and run `setup` again; only the password and the token
  have to be stored by hand.
- **The manual procedure** (create the app, upload the certificate, pre-approve it, relax IP restrictions, enable CDC)
  is still described step by step in the
  [CDC source example README](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#oauth-with-jwt-bearer-flow),
  with screenshots.

## 🧠 CLI reference

[playground salesforce setup](/playground%20salesforce%20setup) · [playground salesforce check](/playground%20salesforce%20check) ·
[playground secrets set](/playground%20secrets%20set)
