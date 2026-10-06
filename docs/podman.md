# 🦭 Using Podman instead of Docker

The playground can run on [Podman](https://podman.io) instead of Docker, with nothing to change in
the examples.

It always drives the container engine through the `docker` CLI and the `docker compose` plugin. With
Podman you keep both, and point them at the **rootful Podman socket** with `DOCKER_HOST`. The
playground detects it and adapts on its own:

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

## 🍏 Setup on macOS

```bash
podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100
podman machine start

export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"

playground doctor
```

- The playground needs at least 8GB of memory.
- Do not pass any `-v` to `podman machine init`. The defaults share `/Users`, `/private` and
  `/var/folders`, which is what the playground mounts from, and any `-v` replaces them.
- An existing machine can be switched to rootful with
  `podman machine stop && podman machine set --rootful && podman machine start`.

## 🐧 Setup on Linux

```bash
# podman, plus netavark and aardvark-dns so that containers resolve each other by name
sudo apt-get install -y podman netavark aardvark-dns    # or: sudo dnf install -y podman

# rootful socket, made accessible to your user's group
sudo mkdir -p /etc/systemd/system/podman.socket.d
printf '[Socket]\nSocketMode=0660\nSocketGroup=%s\n' "$(id -gn)" | sudo tee /etc/systemd/system/podman.socket.d/99-playground.conf
sudo systemctl daemon-reload
sudo systemctl enable --now podman.socket

export DOCKER_HOST="unix:///run/podman/podman.sock"

playground doctor
```

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

## 🤖 CI

The CI workflow has a `container_engine` input. Start it with `podman` from the GitHub UI
(*Actions* > *CI* > *Run workflow*), or from the CLI:

```bash
playground start-ci --podman --test-list "connect/connect-gcp-gcs-sink"
```

The job runs `scripts/ci-setup-podman.sh` first, which installs Podman on the runner, stops Docker,
starts the rootful socket, exports `DOCKER_HOST` and runs `playground doctor`. Its jobs are marked 🦭.

Podman results are stored with a `-podman` suffix, next to the Docker ones: they do not change the
README badges, and do not open or close `🔥` issues.

## ✍️ Writing an example or a reproduction model

Never bind mount `/tmp` literally, use the resolved path the playground provides:

```bash
docker run -v ${PLAYGROUND_HOST_TMP_DIR}:/tmp ...          # instead of -v /tmp:/tmp
docker run -v "$(host_path "$file")":/data/file ...       # for a path that may be under /tmp
```

and in a docker compose override:

```yaml
    volumes:
      - ${PLAYGROUND_HOST_TMP_DIR:-/tmp}:/tmp
```

On Linux and with Docker Desktop this is the same as `/tmp`, so it works with every engine.

## ✅ Verified

On macOS, rootful `podman machine`:

| Example | Environment |
| --- | --- |
| `connect/connect-filestream-sink` | `plaintext`, `2way-ssl`, `ldap-authorizer-sasl-plain` |
| `connect/connect-jdbc-ibmdb2-source` (`privileged: true`) | `plaintext` |
| `connect/connect-aws-s3-sink` | `plaintext` |
| `connect/connect-gcp-gcs-sink` | `plaintext` |
