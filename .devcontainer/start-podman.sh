#!/bin/bash
# postStartCommand of .devcontainer/devcontainer.json: starts the rootful podman API socket that
# 'playground switch-podman' looks for, /run/podman-api/podman.sock, readable by the codespace user.
# On a Linux laptop systemd's podman.socket does it (see docs/how-to-use.md); a codespace has no systemd, so the
# service is started here, each time the codespace starts (/run does not survive a restart).
# Docker stays the default engine: nothing changes until you run 'playground switch-podman'.
# Best effort: a failure here never breaks the codespace.

podman_socket="/run/podman-api/podman.sock"

if ! command -v podman > /dev/null 2>&1
then
  exit 0
fi

if [ -S "$podman_socket" ] && curl -fsS --unix-socket "$podman_socket" http://d/_ping > /dev/null 2>&1
then
  exit 0
fi

sudo mkdir -p "$(dirname "$podman_socket")"
sudo chmod 0755 "$(dirname "$podman_socket")"
sudo rm -f "$podman_socket"
# --time=0: never exits when idle. setsid + nohup: survives the end of postStartCommand.
# The log is written by the codespace user on purpose, so that it can be read without sudo
# shellcheck disable=SC2024
sudo setsid nohup podman system service --time=0 "unix://$podman_socket" > /tmp/podman-service.log 2>&1 < /dev/null &

for _ in $(seq 1 30)
do
  [ -S "$podman_socket" ] && break
  sleep 1
done
if [ ! -S "$podman_socket" ]
then
  echo "⚠️ the podman socket $podman_socket did not start, see /tmp/podman-service.log"
  exit 0
fi
sudo chown "$(id -u):$(id -g)" "$podman_socket"
sudo chmod 0660 "$podman_socket"
echo "🦭 podman socket ready on $podman_socket: 'playground switch-podman' runs the examples on podman, 'playground switch-docker' goes back"
exit 0
