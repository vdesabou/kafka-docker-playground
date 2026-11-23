# ☁️ ServiceNow examples: set up a developer instance

The ServiceNow examples run against a **ServiceNow instance**:

- self-managed: `connect/connect-servicenow-source`, `connect/connect-servicenow-sink`;
- fully managed: `ccloud/fm-servicenow-source`, `ccloud/fm-servicenow-v2-source`, `ccloud/fm-servicenow-sink`.

They use a free **Personal Developer Instance** (PDI) and its user `admin`: the sources read the `incident` table,
the sinks write to `u_test_table`, which they create. Most failures come from the PDI itself: it **hibernates** when
unused, is **released** after about 10 days without use, and recent releases refuse basic authentication for `admin`
unless its Identity Type is Machine.

`playground account servicenow setup` normalizes the URL, wakes the instance up, fixes basic authentication and
stores the values. `playground account servicenow check` tells you, in a few seconds, in which state the instance is.

?> **TL;DR**: request a PDI on [developer.servicenow.com](https://developer.servicenow.com), run
`playground account servicenow setup --url dev12345 --developer-username <your ServiceNow ID>`, run an example.

## 📋 What you need

| What | Why | How |
| --- | --- | --- |
| A **Personal Developer Instance** and the password of its `admin` | the examples log in as `admin` | [developer.servicenow.com](https://developer.servicenow.com) → sign in → **Request Instance** (it can take a while, details by email) |
| Your **ServiceNow ID** (the developer.servicenow.com login), optional | the examples, and `setup`, wake the instance up when it hibernates | the account you requested the PDI with (no MFA) |
| Docker, to wake the instance up | the wake up runs a Playwright browser in the `mcr.microsoft.com/playwright/python` image | |
| `curl`, `jq` | REST API | |

## 🚀 Step by step

### 1. Run `playground account servicenow setup`

```bash
playground account servicenow setup --url dev12345 --developer-username you@example.com
```

It asks for the passwords not stored yet (without echo), then:

```text
🌐 instance https://dev12345.service-now.com/
🛌 ServiceNow instance https://dev12345.service-now.com/ is hibernating, waking it up (it can take several minutes)
⌛ Waiting up to 900 seconds for the REST API of https://dev12345.service-now.com/ to answer
🛌 ServiceNow instance https://dev12345.service-now.com/ is awake
✅ admin can use the REST API of https://dev12345.service-now.com/
💾 stored SERVICENOW_URL, SERVICENOW_PASSWORD, SERVICENOW_DEVELOPER_USERNAME and SERVICENOW_DEVELOPER_PASSWORD
🩺 the instance now:
…
🎉 the ServiceNow instance is ready for the ServiceNow examples
```

What it does, in order:

| Step | Why |
| --- | --- |
| `dev12345`, `dev12345.service-now.com` or any URL → `https://dev12345.service-now.com/` | the examples build `${SERVICENOW_URL}api/now/…`: the trailing `/` is required |
| Wakes the instance up if it hibernates (your ServiceNow ID, Playwright in Docker), then waits for the REST API | the same helper the examples call before they start |
| Sets the **Identity Type** of `admin` to **Machine** when basic authentication answers 401 | recent releases refuse basic authentication otherwise; the examples do the same |
| Stores the values with `playground secrets set` | read by the examples |

### 2. Check, then run an example

```bash
playground account servicenow check
playground run -f connect/connect-servicenow-source/servicenow-source.sh
```

## 🩺 When something stops working: `playground account servicenow check`

```text
🔑 REST API of https://dev12345.service-now.com/ as admin (basic authentication, like the examples)
✅ Instance awake, admin logged in
✅ Table incident (servicenow sources)
✅ Table u_test_table (servicenow sinks)
✅ SERVICENOW_DEVELOPER_* set: the examples wake the instance up when it hibernates (Docker, Playwright image)

🎉 the ServiceNow instance is ready for the ServiceNow examples
```

| `check` says | Likely cause |
| --- | --- |
| `Instance hibernating` | unused for a while: the examples wake it up when `SERVICENOW_DEVELOPER_*` are set, or `setup`, or **Manage my instance** on developer.servicenow.com |
| `Instance waking up (gateway error)` | it is coming back: a minute or two |
| `Login: HTTP 401 for admin` | wrong `SERVICENOW_PASSWORD`, or the Identity Type of `admin` is not Machine: `setup` fixes the latter |
| `nothing answers at …` | wrong URL, or the instance was released: request a new one, then `setup` |
| `SERVICENOW_URL is "…": the examples need "…/"` | the trailing `/` (or `https://`) is missing |

Exit code 1 means the instance does not answer with `admin` logged in.

## ⚙️ Options

| Flag | Use |
| --- | --- |
| `--url <instance>` | `dev12345`, `dev12345.service-now.com` or the full URL |
| `--password <password>` | password of `admin` (asked for without echo when missing) |
| `--developer-username <ServiceNow ID>` / `--developer-password` | lets `setup` and the examples wake the instance up |
| `--no-store` | print the export commands instead of storing the values |

## 💡 Good to know

- **Released instances:** a PDI unused for about 10 days is released, and its URL stops answering. Request a new one
  (a new `devNNNNN` and a new admin password) and run `setup` again.
- **Where the values are stored:** `playground secrets set` stores them in your secrets store (see
  [credentials](deep-dive-secrets.md)). When `secrets.github-repo` is configured (maintainers), it also pushes them to
  the GitHub Actions secrets and variables: use `--no-store` to try another instance without changing CI.

## ☁️ The other accounts

[Accounts of the examples](/accounts.md): the `setup` and `check` commands of every provider, and how they behave.

## 🧠 CLI reference

[playground account servicenow setup](/playground%20account%20servicenow%20setup) · [playground account servicenow check](/playground%20account%20servicenow%20check) ·
[playground secrets set](/playground%20secrets%20set)
