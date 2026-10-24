#!/bin/bash
# EC2 user data of the bore server used by the playground tunnels (Amazon Linux 2023, x86_64 or arm64), see README.md
# __BORE_SECRET__ is replaced by the secret before launching the instance
set -euo pipefail
BORE_VERSION="v0.6.0"

curl -fsSL "https://github.com/ekzhang/bore/releases/download/${BORE_VERSION}/bore-${BORE_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz" | tar --no-same-owner -xz -C /usr/local/bin bore
useradd --system --no-create-home --shell /sbin/nologin bore || true

install -d -m 0750 -o root -g bore /etc/bore
cat > /etc/bore/env << 'ENV'
BORE_SECRET=__BORE_SECRET__
BORE_MIN_PORT=40000
BORE_MAX_PORT=40999
ENV
chown root:bore /etc/bore/env
chmod 0640 /etc/bore/env

cat > /etc/systemd/system/bore.service << 'UNIT'
[Unit]
Description=bore tunnel server (kafka-docker-playground)
After=network-online.target
Wants=network-online.target

[Service]
User=bore
EnvironmentFile=/etc/bore/env
ExecStart=/usr/local/bin/bore server
Restart=always
RestartSec=2
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now bore
