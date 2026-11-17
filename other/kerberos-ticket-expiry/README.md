# Kerberos: the ticket expires, the client breaks at the next reconnect

## Description

A frequent support case with Kerberos (SASL GSSAPI): **"the connector (or the client) worked for hours, then every new
connection failed, and a restart fixed it until the next time"**. With the default ticket lifetime (24 h) nobody can
watch it happen, so the example makes the tickets of its principals last **3 minutes** and reproduces the four ways it
goes wrong, with the exact log lines.

It runs on [environment/kerberos](../../environment/kerberos/README.md) (CP 8+). Nothing of the environment changes:
the lifetime is set on the KDC, for the principals of the example only:

```bash
kadmin.local -q 'modprinc -maxlife "3 minutes" -maxrenewlife "6 minutes" +allow_renewable app_cache@TEST.CONFLUENT.IO'
```

The lifetime of a ticket is the smallest of `ticket_lifetime` of the client `krb5.conf`, `maxlife` of the client
principal, of `krbtgt/` and of the realm: `maxlife` of the client principal is enough. A **renewable** ticket also
needs `maxrenewlife` on `krbtgt/` (the environment sets 11 days). Keep every principal renewable: with
`renew_lifetime` in `krb5.conf` and a principal that is not, Java fails with
`javax.security.auth.login.LoginException: Message stream modified (41)`.

How a Kafka client keeps its ticket (`KerberosLogin`): it logs in again at about 80 % of the lifetime
(`sasl.kerberos.ticket.renew.window.factor` 0.8 and its jitter), never sooner than
`sasl.kerberos.min.time.before.relogin` (60 s), hence 3 minutes and not less. With a keytab it logs in again from the
keytab; with a ticket cache it runs `kinit -R` (`sasl.kerberos.kinit.cmd`). The broker authenticates a connection when
it opens, and again every `connections.max.reauth.ms` when it is set (0 by default: never).

The producers run in the `client` container (`kafka-producer-perf-test`, 2 records/s), with the
`org.apache.kafka.common.security` loggers at `INFO`:

| Producer | Principal | Login |
| --- | --- | --- |
| `A-keytab` | `app_keytab` | `useKeyTab=true`, `/var/lib/secret/app_keytab.key` |
| `B-cache` | `app_cache` | `useTicketCache=true`, after `kinit -r 6m` |
| `C-reauth` | `app_reauth` | `useTicketCache=true`, after `kinit -r 6m`, broker with `connections.max.reauth.ms=60000` |

The example checks:

1. **keytab**: `A-keytab` logs in again every ~2m25s and keeps sending
2. **ticket cache**: `kinit -R` works until the renew-until time, then the refresh thread of `B-cache` exits. Its open
   connection keeps sending, but a new client on the same cache doesn't start
3. **re-authentication**: with `connections.max.reauth.ms=60000`, the open connection of `C-reauth` is dropped at the
   first re-authentication after the expiry, with no broker restart
4. **keytab out of date**: the key of `app_keytab` changes on the KDC (`ktadd` without `-norandkey`) and its keytab is
   not redeployed: `A-keytab` keeps working until its next login, then fails it

After 2 and 4, a broker restart makes both producers open new connections, and they never send again. The ticket cache
producer logs only `terminated during authentication` (with a TLS hint, on a `SASL_PLAINTEXT` listener); the keytab
producer, which lost its principal in the failed re-login, `Principal could not be determined from Subject`. The
broker logs nothing: the clients give up before they send a token. At the end, `playground analyze logs` on the logs of the producers must
report the matching known causes.

## How to run

```bash
playground run -f other/kerberos-ticket-expiry/kerberos-ticket-expiry.sh
```

About 17 minutes (5 of them for the environment). The logs of the producers are copied to `/tmp/kerberos-ticket-expiry`, the `analyze logs` report to
`/tmp/kerberos-ticket-expiry-report`.

## What it prints

Lines of a passing run (CP 8.4.1). 1, the keytab, every ~2m25s:

```text
INFO [Principal=app_keytab@TEST.CONFLUENT.IO]: TGT expires: 2026-11-17T16:00:34.000+0000 (org.apache.kafka.common.security.kerberos.KerberosLogin)
INFO Initiating re-login for app_keytab@TEST.CONFLUENT.IO (org.apache.kafka.common.security.kerberos.KerberosLogin)
```

2, the ticket cache at its renew-until time:

```text
WARN [Principal=null]: TGT refresh thread time adjusted from 2026-11-17T16:03:19.641+0000 to 2026-11-17T16:03:29.879+0000 since the former is sooner than the minimum refresh interval (60 seconds) from now. (org.apache.kafka.common.security.kerberos.KerberosLogin)
WARN [Principal=null]: Error when trying to renew with TicketCache, but will retry  (org.apache.kafka.common.security.kerberos.KerberosLogin)
org.apache.kafka.common.utils.internals.Shell$ExitCodeException: kinit: Ticket expired while renewing credentials
WARN [Principal=null]: Could not renew TGT due to problem running shell command: '/usr/bin/kinit -R'. Exiting refresh thread. (org.apache.kafka.common.security.kerberos.KerberosLogin)
```

Depending on the jitter of the refresh, the last ticket (capped by renew-until) can expire in less than the minimum
refresh interval (60 s). The thread then exits with an ERROR that blames the clock, for the same cause:

```text
INFO [Principal=null]: Refreshing now because expiry is before next scheduled refresh time. (org.apache.kafka.common.security.kerberos.KerberosLogin)
ERROR [Principal=null]: NextRefresh: 2026-11-17T15:37:32.208+0000 is in the past: exiting refresh thread. Check clock sync between this host and KDC - (KDC's clock is likely ahead of this host). Manual intervention will be required for this client to successfully authenticate. Exiting refresh thread. (org.apache.kafka.common.security.kerberos.KerberosLogin)
```

A new client on the same cache, once its last ticket has expired:

```text
Caused by: org.apache.kafka.common.KafkaException: javax.security.auth.login.LoginException: Could not login: the client is being asked for a password, but the Kafka client code does not currently support obtaining a password from the user. not available to garner  authentication information from the user
```

4, the keytab out of date, at the next re-login:

```text
WARN [Principal=app_keytab@TEST.CONFLUENT.IO]: Error when trying to re-Login, but will retry  (org.apache.kafka.common.security.kerberos.KerberosLogin)
javax.security.auth.login.LoginException: Checksum failed
WARN [Principal=app_keytab@TEST.CONFLUENT.IO]: No TGT found: will try again at 2026-11-17T16:03:47.960+0000 (org.apache.kafka.common.security.kerberos.KerberosLogin)
```

After the broker restart, the ticket cache producer (2), and at the re-authentication (3), every second:

```text
WARN [Producer clientId=perf-producer-client] Connection to node -1 (broker.kerberos-demo.local/172.19.0.4:9092) terminated during authentication. This may happen due to any of the following reasons: (1) Firewall blocking Kafka TLS traffic (eg it may only allow HTTPS traffic), (2) Transient network issue. (org.apache.kafka.clients.NetworkClient)
```

The keytab producer (4) after the broker restart, at every connection attempt:

```text
WARN [Producer clientId=perf-producer-client] Error connecting to node broker.kerberos-demo.local:9092 (id: 1 rack: null isFenced: false) (org.apache.kafka.clients.NetworkClient)
java.io.IOException: Channel could not be created for socket java.nio.channels.SocketChannel[closed]
Caused by: org.apache.kafka.common.errors.SaslAuthenticationException: Failed to configure SaslClientAuthenticator
Caused by: org.apache.kafka.common.KafkaException: Principal could not be determined from Subject, this may be a transient failure due to Kerberos re-login
```

3, the broker with `connections.max.reauth.ms=60000` logs a re-authentication of the open connection about every
minute, until the first one after the expiry fails (the client logs `terminated during authentication`, the broker
nothing):

```text
INFO Successfully authenticated client: authenticationID=app_reauth@TEST.CONFLUENT.IO; authorizationID=app_reauth@TEST.CONFLUENT.IO. (org.apache.kafka.common.security.authenticator.SaslServerCallbackHandler)
```

`playground analyze logs` reports them as `🎫 Kerberos ticket cache past its renewable lifetime`,
`🎫 Kerberos keytab out of date (key changed on the KDC)`, `🎫 Kerberos re-login failing`,
`🎫 Kerberos ticket not found or not valid` and `🪓 Connection terminated during authentication`.

## Commands

```bash
# the real lifetime and renew-until of a ticket cache
docker exec client bash -c "KRB5CCNAME=/tmp/krb5cc_app_cache klist"

# the limits of a principal, and the key version of a keytab against the KDC
docker exec kdc kadmin.local -q "getprinc app_keytab@TEST.CONFLUENT.IO"
docker exec client klist -kte /var/lib/secret/app_keytab.key

# redeploy the keytab after a key change (the new key, appended to the keytab the client reads)
docker exec kdc kadmin.local -q "ktadd -k /var/lib/secret/app_keytab.key -norandkey app_keytab@TEST.CONFLUENT.IO"
```

## Support recipes

| Customer situation | Change in the example |
| --- | --- |
| "it fails every N hours" | compare N with the ticket lifetime and renew-until of the customer (`klist` on the worker): N = renew-until of a ticket cache is case 2, use a keytab |
| "it broke the day after a password / key change" | case 4: the keytab of the client still has the old key version (`klist -kte` against `kvno <principal>`) |
| it only breaks at a restart, a roll or a rebalance | the expiry happened long before: open connections survive it while `connections.max.reauth.ms` is 0 (case 2 and 4) |
| `connections.max.reauth.ms` is set on the brokers | case 3: the client breaks within that time after the expiry, without any reconnect |
| a connector (Connect worker) instead of a console client | same `KerberosLogin` thread: set `-maxlife` on the principal of the worker (`connect@TEST.CONFLUENT.IO` here) and restart `connect` for a fresh login |
| `Clock skew too great (37)` | not reproduced: the containers share the clock of the host |
