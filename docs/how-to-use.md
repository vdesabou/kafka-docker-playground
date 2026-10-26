
# 🚀 How to use

## 2️⃣ Ways to run

### 💻️ Locally

#### ☑️ Prerequisites

* You just need to have [docker](https://docs.docker.com/get-docker/) with the [compose v2 plugin](https://docs.docker.com/compose/install/) (`docker compose` 2.0.0 or greater) installed on your machine, or [Podman](/how-to-use?id=%f0%9f%a6%ad-using-podman-instead-of-docker) 5.0 or greater !

* Install the [🧠 CLI](/cli) by following [Setup](/cli?id=%f0%9f%9a%9c-setup). [fzf](https://github.com/junegunn/fzf) is required when using CLI (see installation [instructions](https://github.com/junegunn/fzf#installation))

* bash version 4 or higher is required. Mac users can upgrade bash with [brew](https://brew.sh/) by running `brew install bash` and then make sure it is in PATH (`export PATH=/opt/homebrew/bin:$PATH`)

* You also need internet connectivity when running connect tests as connectors are downloaded from Confluent Hub on the fly.

> [!TIP]
> Run [playground doctor](/playground%20doctor) first: it checks that the container engine is reachable, that compose v2 is there and that there is enough memory. It is the one command that still works when the engine is down.

> [!NOTE]
> Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc...Only exceptions are `fzf`, `confluent` and a local Java install for [playground get-jmx-metrics](/playground%20get-jmx-metrics)
> 
> The goal is to have a consistent behavior and only depends on Docker.

> [!WARNING]
> The playground is only tested on macOS (including with [M1 *arm64* chip](/how-to-use?id=%f0%9f%a7%91%f0%9f%92%bb-m1-chip-arm64-mac-support)) and Linux (Ubuntu and Amazon Linux) . It is not tested on Windows, but it should be working with WSL.

> [!ATTENTION]
> On MacOS, the [Docker memory](https://docs.docker.com/desktop/settings-and-maintenance/settings/#resources) should be set to at least 8Gb.

#### 🧑‍💻 M1 chip (ARM64) Mac Support

Examples in the playground have been tested on best effort (since it is a manual process) on M1 Mac (arm64).

arm64 support results are displayed in **[Content](/content.md)** section:

Example:

![arm64_results](./images/arm64_results.jpg)

The badges are:

* ![arm64](https://img.shields.io/badge/arm64-native%20support-green): example works natively.
* ![arm64](https://img.shields.io/badge/arm64-not%20working-red): example **cannot work at all**. You will need to run it using AWS EC2 instance, see [playground ec2](/playground%20ec2) CLI command
* ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange): example is working but emulation is required. 

Docker Desktop now provides **Rosetta 2** virtualization feature, see detailed steps [here](https://levelup.gitconnected.com/docker-on-apple-silicon-mac-how-to-run-x86-containers-with-rosetta-2-4a679913a0d5) on how to enable it, basically, you need to enable this:

![rosetta](./images/arm64_rosetta.jpg)

#### 🔽 Clone the repository

```bash
git clone --depth 1 https://github.com/vdesabou/kafka-docker-playground.git
```

> [!TIP]
> Specifying `--depth 1` only get the latest version of the playground, which reduces a lot the size of the download.

### ☁️ AWS EC2 instance (using Cloud Formation)

If you want to run the playground on an EC2 instance, you can use the AWS Cloud Formation [template](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.yml).

More details [here](https://github.com/vdesabou/kafka-docker-playground/tree/master/cloudformation).

### ✨ AWS EC2 playground ec2 command

The [playground ec2](/playground%20ec2) CLI command creates and manages AWS EC2 instances (using Cloud Formation) to run kafka-docker-playground, and opens them directly in Visual Studio Code using Remote Development (over SSH).

It is what you want for an example that needs far more CPU or memory than you have, one that must run for hours, or one that does not work on arm64.

Main subcommands are `create`, `open`, `list`, `status`, `start`, `stop`, `delete`, `allow-my-ip`, `sync-repro-folder` and `push-secrets`: check [playground ec2](/playground%20ec2) for the full reference.

## 🦭 Using Podman instead of Docker

The playground can run on [Podman](https://podman.io) instead of Docker, with nothing to change in
the examples.

It always drives the container engine through the `docker` CLI and the `docker compose` plugin. With
Podman you keep both, and point them at the **rootful Podman socket** with
[playground switch-podman](/playground%20switch-podman) (or `DOCKER_HOST`). The playground detects it
and adapts on its own:

- image builds use Podman's own builder (`DOCKER_BUILDKIT=0` is set automatically), so images patched
  locally, like the connect image with its extra tools, are used and kept
- bind mounts of `/tmp` use the resolved path, `/private/tmp` on macOS, which a Podman machine shares

Run `playground doctor` to check that your engine is ready. It is the one command that still works
when the engine is down.

```
$ playground doctor
🩺 Checking the container engine
✅ 'docker' CLI found: Docker version 29.8.1
🦭 engine detected: podman
✅ engine is reachable
✅ 'docker compose' is 5.5.1
✅ engine memory is 11GB
✅ builds use the classic builder (DOCKER_BUILDKIT=0)
✅ podman is running rootful
✅ podman network backend is netavark
✅ docker.io is in the podman search registries
✅ the podman machine shares /Users/me
✅ the podman machine shares /private
✅ the podman machine shares /var/folders
🩺 all good, the podman engine is ready for the playground
```

`playground status` also shows which engine is in use.

### 🍏 Setup on macOS

```bash
podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100
podman machine start

playground switch-podman    # points docker and docker compose at the podman socket, ends with playground doctor
```

- The playground needs at least 8GB of memory.
- Do not pass any `-v` to `podman machine init`. The defaults share `/Users`, `/private` and
  `/var/folders`, which is what the playground mounts from, and any `-v` replaces them.
- An existing machine can be switched to rootful with
  `podman machine stop && podman machine set --rootful && podman machine start`.
- Instead of `playground switch-podman`, you can also
  `export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"`.

### 🐧 Setup on Linux

```bash
# podman, plus netavark and aardvark-dns so that containers resolve each other by name
sudo apt-get install -y podman netavark aardvark-dns    # or: sudo dnf install -y podman

# rootful socket, made accessible to your user's group
sudo mkdir -p /etc/systemd/system/podman.socket.d
sudo tee /etc/systemd/system/podman.socket.d/99-playground.conf << EOF
[Socket]
ListenStream=
ListenStream=/run/podman-api/podman.sock
SocketMode=0660
SocketGroup=$(id -gn)
DirectoryMode=0755
EOF
sudo systemctl daemon-reload
sudo systemctl stop podman.service
sudo systemctl enable --now podman.socket
sudo systemctl restart podman.socket

playground switch-podman    # points docker and docker compose at the podman socket, ends with playground doctor
```

- The socket is moved out of `/run/podman`, which Podman creates as `0700 root`: a socket in there
  stays unreachable for a regular user whatever its own permissions.
- Instead of `playground switch-podman`, you can also `export DOCKER_HOST="unix:///run/podman-api/podman.sock"`.
- Use the **real compose v2 plugin**, not `podman-compose`. `podman-compose` is a separate
  reimplementation with only partial support for `profiles:` and `build:`, which the playground relies
  on heavily.
- No `docker` CLI on the machine? Install `docker-ce-cli` and `docker-compose-plugin` from Docker's
  repository; neither needs the Docker daemon.
- On distributions with SELinux enforcing (Fedora, RHEL), add this to
  `/etc/containers/containers.conf`, because the playground's bind mounts are not labelled:

  ```toml
  [containers]
  label = false
  ```

### 🔀 Switching between Docker and Podman

[playground switch-podman](/playground%20switch-podman) creates a `podman` docker context, so the switch applies to your current shell and to new ones, with nothing to export (on macOS, the podman machine is started if needed).

[playground switch-docker](/playground%20switch-docker) restores the docker context that was active before. Both commands end with `playground doctor`.

> [!WARNING]
> Containers are not moved between engines: stop the running example first.

> [!NOTE]
> An exported `DOCKER_HOST` takes precedence over the docker context: while it is set, `playground switch-docker` and `playground switch-podman` have no effect. Run `unset DOCKER_HOST` (and remove it from your shell profile) to use them. `playground doctor` shows `🔌 DOCKER_HOST is …` when it is set.

## 🏎️ Start an example

Check the list of examples in the **[Content](/content.md)** section and simply use [playground run](/playground%20run) CLI command!

🎬 New here? The bite size session [Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) shows both ways and the options, in about 4 minutes.


> [!NOTE]
> When some environment variables are required, it is specified in the corresponding `README` file
> 
> Examples:
> 
> * [AWS S3 sink connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink#aws-setup): file `~/.aws/credentials` or environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are required.
> 
> * [Zendesk source connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-zendesk-source#how-to-run): arguments `ZENDESK_URL`, `ZENDESK_USERNAME` and `ZENDESK_PASSWORD` are required (you can also pass them as environment variables)
>

If there are missing environment variables, you'll need to fix it: [playground secrets check](/playground%20secrets%20check) tells you which ones, and [playground secrets set](/playground%20secrets%20set) stores them once for all your runs (see [below](/how-to-use?id=🔐-storing-credentials-with-playground-secrets)):

<video src="videos/secrets.mp4" autoplay loop muted playsinline controls width="100%"></video>

### 🕹️ The playground run menu

Running [playground run](/playground%20run) without `-f` opens an interactive menu: pick a category and an example, then select options (use `<tab>` to select several at once) before running it.

<video src="videos/run-menu.mp4" autoplay loop muted playsinline controls width="100%"></video>

* on/off options are toggles, `[x]` when enabled: select one again to disable it
* options that take a value show it once set, for example `🎯 CP version (all components)  --tag  [8.2.0]` (credentials only show `[set]`)
* only the options that apply to the example are shown (for example no connector version for an example without connector, no 🔐 Environment for an example that starts its own environment)
* the preview pane shows the flags that will be used, and warns about combinations that would not work: an error (for example legacy Control Center with CP 8, `--enable-kraft` with CP < 7.4) replaces "🚀 Run the example !" until it is fixed, a warning (for example Control Center with a community image) is only displayed. The same check runs before anything is stopped when not using the menu.
* actions: 🔀 switch to another example in the same folder, keeping the selected options, 🧪 create a reproduction model from the example (see [playground repro bootstrap](/playground%20repro%20bootstrap)), and ⚙️ change the CLI preferences (see below)

Esc or Ctrl-C quits without changing anything. The equivalent `playground run -f <example> <flags>` command is saved in the history ([playground history](/playground%20history), [playground re-run](/playground%20re-run)) and, on macOS, copied to the clipboard (disable with `playground config clipboard false`).

#### ⚙️ CLI preferences

The **⚙️ CLI preferences (playground config)** action opens a submenu with every [playground config](/playground%20config) preference and its current value (`default: …` when it was never set):

![playground run menu: CLI preferences entry](./images/run_menu_config_entry.png)

![playground run menu: CLI preferences submenu](./images/run_menu_config_preferences.png)

* editor used to open files, folders searched for connector zip or jar, copy of the connector config to the clipboard (macOS only)
* kill all containers before each run, deletion of the Confluent Cloud resources left by the last run (`ask`, `true` or `false`), check that the repository is up to date
* masked run log of each run, and its folder (see [📄 Sharing a run](/how-to-use?id=📄-sharing-a-run-the-masked-run-log))
* whether fully managed connectors and Grafana are opened in the browser, and in which browser

Pick a preference, then its new value: `true`/`false`, or a list of suggestions for the editor and the browser (type another one and use `<option+enter>`). The change is saved right away, exactly as the matching `playground config` command would, and the submenu stays open until 🔙 Back to the example menu.

#### 📄 Sharing a run: the masked run log

Every `playground run` also writes its output to a text file, with passwords, api keys and tokens masked, ready to attach to a ticket or to send to a colleague or engineering. Its path is the last line of the run:

```
📄 masked log of this run (4 secrets masked), to share with a colleague or engineering: ~/.local/state/kafka-docker-playground/run-logs/filestream-sink-20261026-151903.log
```

The file starts with a header (the command to re-run, environment, CP and connector versions, playground commit, host and container engine, duration and result), then the whole output of the run without colors and, for a failure, the errors of the connect container (`playground container logs -c connect --errors`):

```
# 📄 playground run log
command:      playground run -f connect/connect-filestream-sink/filestream-sink.sh --tag=8.3.2
environment:  plaintext
CP version:   8.3.2
connector:    default
playground:   1d95feddf
host:         Darwin 27.0.0, docker 29.8.2
started:      2026-10-26T14:19:03Z, duration 0min 23sec
result:       FAILURE (exit code 1)
masking:      secrets are masked with ********, best-effort: review this file before sharing it outside Confluent
```

What is masked: the values of the credentials exported for the example (loaded from `playground secrets`, or variables named `*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*KEY*`, `*CREDS*`…), the api keys of `playground.ini`, `~/.aws/credentials`, the value of secret-looking keys (`"connection.password": "…"`, `password=…` in properties, JDBC urls and JAAS configs, `password: …` in yaml), private keys, AWS access key ids, JWTs, `Bearer` tokens and `user:password@` in urls. A secret that the example builds itself is not known in advance: **the masking is best-effort, read the file before sharing it outside Confluent**.

* `--run-log-file <file>` writes it to that file, `--no-run-log` skips it for one run
* `playground config run-log false` never writes it, `playground config run-log-folder <folder>` changes the folder (default `~/.local/state/kafka-docker-playground/run-logs`, the last 50 files are kept, readable by you only)
* the example still runs in a terminal (it is run under `script`), so colors, prompts and HTML reports behave as before
* nothing is written in CI, which already keeps the output of each run

### 🔐 Storing credentials with playground secrets

Instead of exporting variables in every shell, store them once with [playground secrets](/playground%20secrets): `playground run` then loads automatically the ones the example declares.

```bash
playground secrets set SALESFORCE_PASSWORD    # 🔐 store it, prompted
playground secrets check -f <example>         # ✅ what is still missing
playground run -f <example>                   # 🚀 loaded for you
```

They are stored in `~/.config/kafka-docker-playground` (never in the repository), with credential values kept in a backend such as macOS Keychain, secret-tool, pass, 1Password or HashiCorp Vault (see [playground secrets backend](/playground%20secrets%20backend)).

> [!TIP]
> 🍪 The deep dive [Credentials and the 1Password setup](/deep-dive-secrets.md) explains the store, the backends, profiles, and how to set up 1Password (desktop app, service account, shared team vault), with a hands-on lab.

## 🌤️ Confluent Cloud examples

Simply use [playground run](/playground%20run) command ! Below, the menu shows the Confluent Cloud options of a fully managed connector example (it quits before running it):

<video src="videos/ccloud-run-menu.mp4" autoplay loop muted playsinline controls width="100%"></video>

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the new cluster by using flags with [playground run](/playground%20run) command or just by setting environment variables:

* `--cluster-type` (or `CLUSTER_TYPE` environment variable): the type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `--cluster-cloud` (or `CLUSTER_CLOUD` environment variable): The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `--cluster-region` (or `CLUSTER_REGION` environment variable): The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope` for azure and `europe-west2` for gcp)
* `--cluster-environment` (or `ENVIRONMENT` environment variable) (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup, in addition to previous ones:

* `--cluster-name` (or `CLUSTER_NAME` environment variable): The cluster name
* `--cluster-creds` (or `CLUSTER_CREDS` environment variable): The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `--cluster-schema-registry-creds` (or `SCHEMA_REGISTRY_CREDS` environment variable) (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

🤖 For [Fully Managed connectors](/content?id=%f0%9f%a4%96-fully-managed-connectors), as examples are [dependent of cloud providers](https://docs.confluent.io/cloud/current/connectors/index.html#cloud-platforms-support), you have the possibility to define specific existing clusters per cloud provider:

* AWS:

```bash
AWS_CLUSTER_NAME
AWS_CLUSTER_REGION
AWS_CLUSTER_CLOUD
AWS_CLUSTER_CREDS
```

* GCP:

```bash
GCP_CLUSTER_NAME
GCP_CLUSTER_REGION
GCP_CLUSTER_CLOUD
GCP_CLUSTER_CREDS
```

* AZURE:

```bash
AZURE_CLUSTER_NAME
AZURE_CLUSTER_REGION
AZURE_CLUSTER_CLOUD
AZURE_CLUSTER_CREDS
```

For example, if you're running an AZURE Fully Managed connector example and `AZURE_CLUSTER_NAME` is set, then this cluster will be used even if you have `CLUSTER_NAME` set.

### 👤 Fully managed connectors with a service account

Add `--ccloud-service-account` (or tick *👤 Connector service account* in the run menu) to run the fully managed connectors of an example with a [service account](https://docs.confluent.io/cloud/current/connectors/service-account.html) (`kafka.auth.mode=SERVICE_ACCOUNT`) and the ACLs of the documentation, instead of an API key. Then remove or deny ACLs with `playground rbac acl --connector <connector>` to reproduce authorization errors: see [Fully managed connectors with a service account](/reusables?id=%f0%9f%91%a4-fully-managed-connectors-with-a-service-account).

![playground run menu: Connector service account toggle](./images/run_menu_ccloud_service_account.png)

## 🪄 Specify versions

[playground run](/playground%20run) command allows you to do that very easily !

![specify versions](./images/versions.jpg)

### 🎯 For Confluent Platform (CP)

By default, the latest Confluent Platform version supported by the playground is used (currently CP 8.4.0, which is [KRaft](/how-to-use?id=📡-kraft-mode) only). Use `--tag` option of [playground run](/playground%20run) (or `TAG` environment variable) to run with another version.

> [!TIP]
> You can also change cp version while running an example using [playground update-version](/playground%20update-version)

### 🔗 For Connectors

By default, for each connector, the latest available version on [Confluent Hub](https://www.confluent.io/hub/) is used. 

The only 2 exceptions are:

* replicator which is using same version as CP (but you can force a version using `REPLICATOR_TAG` environment variable)
* JDBC which is using same version as CP (but only for CP version lower than 6.x)

Each latest version used is specified on the [Connectors list](/content?id=%f0%9f%94%97-connectors).

The playground has 3 different ways to use different connector version when running a connector example:

1. Specify the connector version (`--connector-tag` using [playground run](/playground%20run) command)

2. Specify a connector ZIP file (`--connector-zip` using [playground run](/playground%20run) command)

3. Specify a connector JAR file (`--connector-jar` using [playground run](/playground%20run) command)

*Example:*

```bash
00:33:47 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/kafka-connect-http-1.3.1-SNAPSHOT.jar
/usr/share/confluent-hub-components/confluentinc-kafka-connect-http/lib/kafka-connect-http-1.2.4.jar
00:33:48 ℹ️ 👷 Building Docker image confluentinc/cp-server-connect-base:cp-6.2.1-kafka-connect-http-1.2.4-kafka-connect-http-1.3.1-SNAPSHOT.jar
00:33:48 ℹ️ Remplacing kafka-connect-http-1.2.4.jar by kafka-connect-http-1.3.1-SNAPSHOT.jar
```

When jar to replace cannot be found automatically, the user is able to select the one to replace automatically:

```bash
11:02:43 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/debezium-connector-postgres-1.4.0-SNAPSHOT.jar
ls: cannot access '/usr/share/confluent-hub-components/debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar': No such file or directory
11:02:44 ❗ debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar does not exist, the jar name to replace could not be found automatically
11:02:45 ℹ️ Select the jar to replace:
1) debezium-api-1.4.0.Final.jar
2) debezium-connector-postgres-1.4.0.Final.jar
3) debezium-core-1.4.0.Final.jar
```

> [!WARNING]
> You can use both `--connector-tag` and `--connector-jar` at same time (along with `--tag`), but `--connector-tag` and `--connector-zip` are mutually exclusive.

> [!NOTE]
> For more information about the Connect image used, check [here](/how-it-works?id=🔗-connect-image-used).

> [!TIP]
> You can also change connector(s) version(s) while running an example using [playground update-version](/playground%20update-version)

## 🐳 Overriding Confluent Platform Docker images and tags

Community images can be selected with [playground run](/playground%20run) options (or in the menu):

* `--connect-community-image`: connect runs `confluentinc/cp-kafka-connect` instead of `confluentinc/cp-server-connect` (monitoring interceptors are disabled)
* `--kafka-community-image`: broker and controller run `confluentinc/cp-kafka` instead of `confluentinc/cp-server` (Confluent Metrics Reporter and Telemetry Reporter are disabled)

Docker images being used can also be overridden by exporting following environment variables:

* zookeeper (`CP_ZOOKEEPER_IMAGE`) (CP < 8 only)
* kafka (`CP_KAFKA_IMAGE`)
* connect (`CP_CONNECT_IMAGE`)
* schema-registry (`CP_SCHEMA_REGISTRY_IMAGE`)
* control-center (`CP_CONTROL_CENTER_IMAGE`)
* ksqlDb (`CP_KSQL_IMAGE`)
* ksqlDB CLI (`CP_KSQL_CLI_IMAGE`)
* rest-proxy (`CP_REST_PROXY_IMAGE`)

Docker images tags being used can be overridden by exporting following environment variables (or with the [playground run](/playground%20run) option, when there is one):

* zookeeper (`CP_ZOOKEEPER_TAG`) (CP < 8 only)
* kafka (`CP_KAFKA_TAG`)
* connect (`CP_CONNECT_TAG`, `--connect-tag`)
* schema-registry (`CP_SCHEMA_REGISTRY_TAG`, `--schema-registry-tag`, not for ccloud examples)
* control-center (`CP_CONTROL_CENTER_TAG`, `--control-center-tag`): a Control Center Next Gen version (for example `2.6.1`, default `latest`), or a CP version with legacy Control Center
* ksqlDb (`CP_KSQL_TAG`) and ksqlDB CLI (`CP_KSQL_CLI_TAG`): `--ksqldb-tag` sets both
* rest-proxy (`CP_REST_PROXY_TAG`)

*Example:* schema registry 7.9.1 with everything else on 8.3.2:

```bash
playground run -f datagen-source<tab> --schema-registry-tag 7.9.1
```

## 📡 Kraft mode

[Kraft](https://docs.confluent.io/platform/current/kafka-metadata/kraft.html) is enabled by default when used with CP 8+. For CP 7.4 to 7.9, you can force it with `--enable-kraft` option of [playground run](/playground%20run) (or by setting environment variable `ENABLE_KRAFT`). It is refused for CP < 7.4, and has no effect with CP 8+.

In Kraft mode, a `controller` container replaces the `zookeeper` container (its JMX port is `10005`). ZooKeeper is only used with CP < 8 when `ENABLE_KRAFT` is not set.

## ⛳ Options

Selecting options is really easy with [playground run](/playground%20run) menu:

![options](./images/options.jpg)

### 🚀 Enabling ksqlDB

By default, `ksqldb-server` and `ksqldb-cli` containers (see [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)) are not started for every test.

You can enable this with `--enable-ksqldb` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_KSQLDB=1` in your shell.

### 💠 Enabling Control Center

By default, `control-center` container (see [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)) is not started for every test.

You can enable this with `--enable-control-center` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_CONTROL_CENTER=1` in your shell.

Control Center "Next Gen" (image `confluentinc/cp-enterprise-control-center-next-gen`) is used by default. If you want to use the legacy image, use `--enable-legacy-control-center` option of [playground run](/playground%20run) (it also enables Control Center), or set environment variable `ENABLE_LEGACY_CONTROL_CENTER=1` in your shell. Legacy Control Center is only available for CP < 8.

Use `--control-center-tag` to select the Control Center version (see [above](/how-to-use?id=🐳-overriding-confluent-platform-docker-images-and-tags)).

Control Center is reachable at http://127.0.0.1:9021

### 🐺 Enabling Conduktor Platform

By default, [`Conduktor Platform`](https://www.conduktor.io) container is not started for every test. 

You can enable this with `--enable-conduktor` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_CONDUKTOR=1` in your shell.

Conduktor is reachable at [http://127.0.0.1:8080/console](http://127.0.0.1:8080/console) (`admin`/`admin`).

### 🧲 Enabling REST Proxy

By default, `rest-proxy` container is not started for every test.

You can enable this with `--enable-rest-proxy` option of [playground run](/playground%20run).

### 🔢 Enabling multiple brokers

By default, there is only one kafka node enabled. To enable three nodes, select it in menu or use `--enable-multiple-brokers` option of [playground run](/playground%20run).

### 🥉 Enabling multiple connect workers

By default, there is only one connect node enabled. To enable three connect nodes, select it in menu or use `--enable-multiple-connect-workers` option of [playground run](/playground%20run).

`connect2` and `connect3` get the `connect` configuration of the example: the playground generates a copy of the example's docker-compose override file with them under `/tmp/playground-connect-workers/`, the example's own file is not modified.

### 🌀 Enabling SQL Datagen

For the JDBC, Debezium, Oracle CDC and XStream source examples (Oracle, MySQL, MariaDB, PostgreSQL, SQL Server, self-managed and fully managed), the `--enable-sql-datagen` option of [playground run](/playground%20run) keeps inserting rows once the example is done: the `benchmark-load.bash` of the example, one row per transaction, in 5 parallel sessions, for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION`). See [Databases: keep a load running](/reusables?id=%f0%9f%8c%aa%ef%b8%8f-databases-keep-a-load-running-with-enable-sql-datagen).

### 🎯 Starting only some services

Set environment variable `START_SERVICES` with a space-separated list of services (example: `START_SERVICES="broker schema-registry connect"`) to start only those services of the environment.

### 📊 Enabling JMX Grafana

By default, Grafana dashboard using JMX metrics is not started for every test.

You can enable this with `--enable-jmx-grafana` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_JMX_GRAFANA=1` in your shell.

📊 Grafana is reachable at [http://127.0.0.1:3000](http://127.0.0.1:3000)
🛡️ Prometheus is reachable at [http://127.0.0.1:9090](http://127.0.0.1:9090) (it scrapes the JMX exporters every 15 s)
📛 [Pyroscope](https://pyroscope.io/docs/) is reachable at [http://127.0.0.1:4040](http://127.0.0.1:4040)

> [!TIP]
> [playground connector benchmark](/reusables?id=%f0%9f%93%8a-grafana) annotates its measure on the Kafka Connect, connector and Kafka cluster dashboards, and links to them at the time of the run.

#### Grafana dashboards

List of provided dashboards:
 - Confluent Platform overview
 - Zookeeper cluster (CP < 8 only)
 - Kafka cluster
 - Kafka topics
 - Kafka quotas
 - Schema Registry cluster
 - Kafka Connect cluster
 - ksqlDB cluster
 - Kafka streams RocksDB
 - Kafka Clients
 - Oracle CDC source Connector
 - Oracle XStream CDC source Connector
 - Debezium CDC source Connectors
 - Mongo source and sink Connector
 - Kafka lag exporter (no screenshot)
 - Cluster Linking (no screenshot)
 - Flink (no screenshot)


<!-- tabs:start -->

#### **Confluent Platform overview**

![Confluent Platform overview](images/confluent-platform-overview.png)

#### **Zookeeper cluster (CP < 8 only)**

![Zookeeper cluster dashboard](images/zookeeper-cluster.png)

#### **Kafka cluster**

![Kafka cluster dashboard 0](images/kafka-cluster-0.png)
![Kafka cluster dashboard 1](images/kafka-cluster-1.png)

#### **Kafka topics**

![Kafka topics](images/kafka-topics.png)

#### **Kafka quotas**

For Kafka to output quota metrics, at least one quota configuration is necessary.

A quota can be configured using:

```bash
playground container exec -c broker --command "kafka-configs --bootstrap-server broker:9092 --alter --add-config 'producer_byte_rate=10000,consumer_byte_rate=30000,request_percentage=0.2' --entity-type users --entity-name unknown --entity-type clients --entity-name unknown"
```

![Kafka quotas](images/kafka-quotas.png)

#### **Schema Registry cluster**

![Schema Registry cluster](images/schema-registry-cluster.png)

#### **Kafka Connect cluster**

![Kafka Connect cluster dashboard 0](images/kafka-connect-cluster-0.png)
![Kafka Connect cluster dashboard 1](images/kafka-connect-cluster-1.png)

#### **ksqlDB cluster**

![ksqlDB cluster dashboard 0](images/ksqldb-cluster-0.png)
![ksqlDB cluster dashboard 1](images/ksqldb-cluster-1.png)

#### **Kafka streams RocksDB**

![kafkastreams-rocksdb 0](images/kafkastreams-rocksdb.png)

#### **Kafka Clients**

![Kafka Producer](images/kafka-producer.png)

![Kafka Consumer](images/kafka-consumer.png)

#### **Oracle CDC source Connector**

![oraclecdc](images/oraclecdc.jpg)

#### **Oracle XStream CDC source Connector**

![oraclexstreamcdc](images/oraclexstreamcdc.jpg)

#### **Debezium CDC source Connectors**

![debezium](images/debezium.png)

#### **Mongo source and sink Connector**

![mongo](images/mongo.png)

<!-- tabs:end -->


### 🐈‍⬛ Enabling kcat

By default, [edenhill/kcat](https://github.com/edenhill/kcat) is not started for every test. 

You can enable this with `--enable-kcat` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_KCAT=1` in your shell.

Then you can use it with:

```bash
playground container exec -c kcat --command "kcat -b broker:9092 -L"
```

### 🐹 Enabling Flink

By default, Flink task/jobmanager is not started for every test. 

You can enable Flink for any connector using plaintext deployment with `--enable-flink` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_FLINK=1` in your shell. 

Once enabled, the CLI will ask if you need to download any connectors. Based on the response, you can download one or more connectors from Flink's [maven](https://repo.maven.apache.org/maven2/org/apache/flink/) repository. 

Additionally, you can start Flink in any of the available [deployment modes](https://nightlies.apache.org/flink/flink-docs-master/docs/deployment/overview/#deployment-modes) by navigating to the respective directory:

- `kafka-docker-playground/`
  - `flink/`
    - `flink_app_mode/start.sh`
    - `flink_session_mode/start.sh`
    - `flink_session_sql_mode/start.sh`


🐹 Flink UI is reachable using [http://127.0.0.1:8081](http://127.0.0.1:8081) within the flink child directory. If you enable Flink by starting connector deployment, [http://127.0.0.1:18081](http://127.0.0.1:18081) will be used. 

## 🔢 JMX Metrics

JMX metrics are available locally on those ports:

* broker: `10000` (`broker2`: `12000`, `broker3`: `13000` with multiple brokers)
* schema-registry: `10001`
* connect: `10002` (`connect2`: `10022`, `connect3`: `10032` with multiple connect workers)
* ksqldb-server: `10003`
* controller: `10005` (Kraft mode)
* zookeeper: `9999` (CP < 8 only)

In order to easily gather JMX metrics, you can use [playground get-jmx-metrics](/playground%20get-jmx-metrics) command. `--container` (`-c`) can be repeated (default is `connect`), `--domain` (`-d`) restricts the list of domains and `--open` (`-o`) saves the output to a file and opens it with your editor:

```bash
playground get-jmx-metrics -c connect -c broker --domain "kafka.server"
```

Example (without specifying domain):

```bash
$ playground get-jmx-metrics -c connect
17:35:35 ❗ You did not specify a list of domains, all domains will be exported!
17:35:35 ℹ️ This is the list of domains for component connect
JMImplementation
com.sun.management
java.lang
java.nio
java.util.logging
jdk.management.jfr
kafka.admin.client
kafka.connect
kafka.consumer
kafka.producer
17:35:38 ℹ️ JMX metrics are available in /tmp/jmx_metrics.log file
```

Example (specifying domain):

```bash
$ playground get-jmx-metrics -c connect -d "kafka.connect kafka.consumer kafka.producer"
17:38:00 ℹ️ JMX metrics are available in /tmp/jmx_metrics.log file
```

> [!WARNING]
> Local install of Java `JDK` (at least 1.8) is required to run `playground get-jmx-metrics`

## 📝 See properties file

Because the playground uses **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file.

In order to easily see the end result properties file, you can use [playground container get-properties](/playground%20container%20get-properties) command

*Example:*

```bash
$ playground get-properties -c connect
bootstrap.servers=broker:9092
config.providers.file.class=org.apache.kafka.common.config.provider.FileConfigProvider
config.providers=file
config.storage.replication.factor=1
config.storage.topic=connect-configs
connector.client.config.override.policy=All
consumer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
group.id=connect-cluster
internal.key.converter.schemas.enable=false
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter.schemas.enable=false
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter=org.apache.kafka.connect.storage.StringConverter
log4j.appender.stdout.layout.conversionpattern=[%d] %p %X{connector.context}%m (%c:%L)%n
log4j.loggers=org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
offset.storage.replication.factor=1
offset.storage.topic=connect-offsets
plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-http
producer.client.id=connect-worker-producer
producer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
rest.advertised.host.name=connect
rest.port=8083
status.storage.replication.factor=1
status.storage.topic=connect-status
topic.creation.enable=true
value.converter.schema.registry.url=http://schema-registry:8081
value.converter.schemas.enable=false
value.converter=io.confluent.connect.avro.AvroConverter
```

## ♻️ Re-create containers

Because the playground uses **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file and also `docker-compose` files in the playground depends on environment variables to be set.

For these reasons, if you want to make a change in one of the `docker-compose` files (without restarting the example from scratch), it is not simply a matter of doing `docker compose up -d` 😅!

However, when you execute an example, you get in the output the [playground container recreate](/playground%20container%20recreate) in order to easily re-create modified container(s) 🥳.

*Example:*

```bash
12:02:18 ℹ️ ✨If you modify a docker-compose file and want to re-create the container(s),
 run cli command playground container recreate
```

So you can modify one of the `docker-compose` files (in that case either [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml) or [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml)), and then run [playground container recreate](/playground%20container%20recreate) command:

```bash
playground container recreate
```

Only the containers whose definition changed (for example `connect` and `http-service-no-auth` after editing [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml)) are re-created, the others are left running.
