# SFTP Sink connector

## Objective

Quickly test the [SFTP Sink](https://docs.confluent.io/kafka-connectors/sftp/current/sink-connector/overview.html) connector.

## Prerequisites

* With CP 8.x, connector version 3.2.0 or later.
* `ssh-keygen` and `openssl` on the host for the SSH key / PEM file variants.
* `sftp-sink-kerberos.sh` is not supported with the `cfk` environment.

## How to run

```bash
playground run -f sftp-sink.sh
```

| Script | Description |
| --- | --- |
| `sftp-sink.sh` | Username/password authentication, Avro format |
| `sftp-sink-ssh-key.sh` | SSH key authentication (`tls.private.key` / `tls.public.key` with a passphrase), CSV format |
| `sftp-sink-ssh-pem-file.sh` | SSH key authentication with a PEM file (`tls.pemfile`), CSV format |
| `sftp-sink-kerberos.sh` | Kerberos authentication (`kerberos.keytab.path`, `kerberos.user.principal`) against an SSH server with a KDC, Avro format |

## What the script does

1. Starts an SFTP server (for the SSH key variants, an RSA key pair with passphrase `mypassword` is generated first; for Kerberos, principals and keytabs are created in the KDC and copied to `connect` and `ssh-server`).
2. Creates the SFTP Sink connector reading topic `test_sftp_sink` (`flush.size=3`, working dir `/upload`).
3. Produces 10 Avro records (`{"f1":"value%g"}`) to `test_sftp_sink`.
4. Lists the files written in `upload/topics/test_sftp_sink/partition=0/` on the SFTP server.
5. For the Avro variants, copies the first file locally and displays it with `playground tools read-avro-file`.

Expected output:

```
test_sftp_sink+0+0000000000.avro  test_sftp_sink+0+0000000003.avro  test_sftp_sink+0+0000000006.avro  test_sftp_sink+0+0000000009.avro

{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
```

## Known issues

* Kerberos: `kinit` has to be run manually in the `connect` container before creating the connector (the script does `kinit sshuser -k -t /tmp/sshuser.keytab`).
