# bore tunnel: a drop-in replacement for ngrok

The fully managed connector examples (`ccloud/fm-*`) that read or write a local container (Postgres, MongoDB, an HTTP
server…) expose it with an `ngrok` compose service, and read its public endpoint from the agent API
(`curl http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url'`).

When `BORE_SERVER` is set, `display_ngrok_warning` builds this folder as `kdp-bore-tunnel:latest` and exports
`NGROK_IMAGE`, which the `ngrok` services use instead of `ngrok/ngrok:latest`. The image:

- takes the same command line (`start --all --log=stdout --config /etc/ngrok.yml`) and reads the same `ngrok.yml`
  (`name:` / `addr: host:port` / `proto: tcp`);
- opens one [bore](https://github.com/ekzhang/bore) tunnel per entry on `BORE_SERVER`, authenticated with `BORE_SECRET`;
- answers `GET :4040/api/tunnels` with `{"tunnels":[{"name","proto":"tcp","public_url":"tcp://<server>:<port>"}]}`, in the
  order of the config file, once every tunnel is up (404 before, the examples keep waiting);
- exits when a tunnel drops, so `restart: unless-stopped` reconnects it.

No example has to change. Without `BORE_SERVER`, ngrok is used as before (`NGROK_AUTH_TOKEN`).

```bash
# once: stored in the playground secrets, loaded by 'playground run' for every example that uses a tunnel
playground secrets set BORE_SERVER --value "$(cat ~/.kdp-bore/server)"
playground secrets set BORE_SECRET --value "$(cat ~/.kdp-bore/secret)"
playground run -f ccloud/fm-chromadb-sink/fully-managed-chromadb-sink.sh
```

(or `export BORE_SERVER=… BORE_SECRET=…`, which always wins over the secrets.)

## The server

CI uses a bore server on a `t4g.nano` (Amazon Linux 2023, arm64) in AWS `eu-west-3`, next to the CI Confluent Cloud
cluster, with an Elastic IP. Inbound:

- TCP `7835`, the bore control port, from anywhere: the bore clients run on GitHub runners and laptops, and all their
  traffic goes through this port. Only clients with the secret can open a tunnel.
- TCP `40000-40999`, the tunnels, only from the egress IPs of the CI Confluent Cloud clusters (AWS, Azure, GCP): only the
  fully managed connectors connect to them. The list is not in the repository: `create-server.sh` reads it from
  `~/.kdp-bore/allowed-cidrs.txt` (one CIDR per line, `#` comments), and opens the ports to everyone without it.

The egress IPs are per cloud region, not per cluster: a laptop run works as long as its connector runs in a cluster of one of
these regions (the CI cluster, or any other cluster there). For another region, get its list and add it to the security group:

```bash
confluent network ip-address list --cloud aws --region eu-west-2 --services CONNECT --address-type EGRESS
aws ec2 authorize-security-group-ingress --region eu-west-3 --group-name kdp-bore-server \
  --ip-permissions 'IpProtocol=tcp,FromPort=40000,ToPort=40999,IpRanges=[{CidrIp=<cidr>,Description=bore tunnels}]'
```

To create it, run [`create-server.sh`](create-server.sh) (`AWS_PROFILE=<profile> tools/bore-tunnel/create-server.sh [region]`): it
generates the secret in `~/.kdp-bore/secret` and launches the instance with [`server-user-data.sh`](server-user-data.sh). The secret and the host are the `BORE_SECRET` and `BORE_SERVER` secrets of the
GitHub repository. Check the server with `bore local 1 --to <host> --secret <secret>`: it prints
`listening at <host>:<port>`.
