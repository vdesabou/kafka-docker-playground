# 🎁 Tips & Tricks

Below is a collection of tips and tricks, all using the [🧠 CLI](/cli).

## 🐳 Container tips

### Tail container logs

Example with `connect` container:

```bash
playground container logs -c connect
```

### Redirect all container logs to a file

Example with `connect` container:

```bash
playground container logs -c connect --open
```

Output:

```bash
23:10:30 ℹ️ Opening /tmp/connect-2023-02-27-23-10-30.log with editor code
```

> [!TIP]
> The editor is set with `playground config editor <editor>` (default is `code`).

### Filter container logs

Keep only the lines that matter, or only the recent ones:

```bash
playground container logs -c connect --grep "ERROR"
playground container logs -c connect --since 10m
playground container logs -c connect --grep "Caused by" --no-follow
```

Get a de-duplicated digest of ERROR/FATAL records:

```bash
playground container logs -c connect --errors --since 10m
```

### Wait for a connector or for records

No fixed `sleep` is needed after creating a self-managed connector: `playground connector create-or-update` waits until the connector and all its tasks are RUNNING, and fails right away, with the stack trace, if a task is FAILED. In a reproduction model, that failure is only a warning, since the connector often fails on purpose:

```bash
playground connector create-or-update --connector my-connector << EOF
{ ... }
EOF

# --wait: fail in a reproduction model too, and wait for fully managed connectors
# --no-wait: don't wait at all, for example to create a connector that is expected to fail
playground connector create-or-update --connector my-connector --no-wait << EOF
{ ... }
EOF

# on an existing connector (--state RUNNING|PAUSED|STOPPED|FAILED)
playground connector wait --connector my-connector --state FAILED --max-wait 120
```

To wait until a source connector has produced data:

```bash
playground topic wait-for-records --topic my-topic --min-expected-messages 10 --max-wait 120
```

### Wait for a log line

Instead of using `sleep`, block until a log line shows up (useful in reproduction models):

```bash
playground container logs -c connect --wait-for-log "Finished starting connectors and tasks" --max-wait 120
```

### Display errors of all containers

The first command to run when an example misbehaves and you do not yet know which component is at fault:

```bash
playground container display-error-all
```

### SSH into container

Example with `connect` container:

```bash
playground container ssh -c connect
```

### Kill all containers

```bash
playground container kill-all
```

### Run some commands

Example with `connect` container:

```bash
playground container exec -c connect --command "whoami"
```

### Run some commands as root

Example with `connect` container:

```bash
playground container exec -c connect --command "whoami" --root
```

### Copy files between local filesystem and container

```bash
playground container cp --source ./file.txt --destination connect:/tmp/file.txt
playground container cp --source connect:/tmp/file.txt --destination ./file.txt
```

### Change the JDK version of a container

Uses Azul Zulu JDK (works with UBI8 images only):

```bash
playground container change-jdk --container connect --version 21
```

### Get IP address of running containers

```bash
playground container get-ip-addresses
```

## 🗳 Topic tips

### Get number of records in a topic

```bash
playground topic get-number-records --topic a-topic
```

> [!NOTE]
> See [playground topic get-number-records](/playground%20topic%20get-number-records) for all options.

### Find which topics take the most disk space

```bash
playground topic get-size
playground topic get-size --show-internal
playground topic list --sort-by-size
```

Shows the size and number of partitions of each topic, largest first. With ccloud environment, sizes come from the Metrics API (`retained_bytes`), which lags a few minutes behind and requires `CONFLUENT_CLOUD_API_KEY` and `CONFLUENT_CLOUD_API_SECRET`.

> [!NOTE]
> See [playground topic get-size](/playground%20topic%20get-size) for all options.

### Check Kafka Connect offsets

```bash
playground connector offsets get
```

or consume the `connect-offsets` topic directly:

```bash
playground topic consume --topic connect-offsets
```

> [!TIP]
> To display the content of `__consumer_offsets`, use [playground topic display-consumer-offsets](/playground%20topic%20display-consumer-offsets).

## 🧠 CLI tips

### Get a status of what is running

```bash
playground status
```

It shows the example currently running, the state of every container, the connectors (versions, status, configuration) and the topics.

### Check that the container engine is ready

```bash
playground doctor
```

It reports which engine is used (Docker or Podman) and checks compose v2, memory and, with Podman, the extra requirements. It is the command to run first when an example fails before a single container starts.
