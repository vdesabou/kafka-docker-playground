# How to ensure high availability of LDAP using DNS SRV Records

## Objective

Quickly test [DNS SRV Records for LDAP](https://ldap.com/dns-srv-records-for-ldap/) in order to ensure high availability of LDAP.

## How to run

Simply run:

```
$ playground run -f start-ldap<tab>
```

or with LDAPS (**this is not working**, see [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/ldap-authorizer-with-ldap-failover/README.md#using-dns-srv-records-with-ldap-over-tls) for details):

```
$ playground run -f start-ldaps<tab>
```

## Details of what the script is doing

3 OpenLDAP servers are started (`ldap`, `ldap2`and `ldap3`)

[BIND9](https://www.isc.org/bind/) DNS server is used in order to create the SRV records:

```yml
  bind:
    build:
      context: ../../other/ldap-authorizer-with-ldap-failover/bind
      args:
        DOMAIN_FILE: "confluent.io-ldap"
    hostname: bind.confluent.io
    container_name: bind
    ports:
    - 53:53/udp
    restart: unless-stopped
    depends_on:
    - ldap
    - ldap2
    - ldap3
    networks:
      testing_net:
        ipv4_address: 172.28.1.1
```

The BIND9 config [file](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/ldap-authorizer-with-ldap-failover/bind/confluent.io-ldap) looks like:

```properties
$TTL    604800
@       IN      SOA     bind.confluent.io. root.confluent.io. (
                  3       ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800 )   ; Negative Cache TTL
;
; name servers - NS records
     IN      NS      bind.confluent.io.

; name servers - A records
bind.confluent.io.          IN      A      172.28.1.1
ldap.confluent.io.          IN      A      172.28.1.2
ldap2.confluent.io.         IN      A      172.28.1.3
ldap3.confluent.io.         IN      A      172.28.1.4

_ldap._tcp.confluent.io. IN SRV 10 50 389 ldap.confluent.io.
_ldap._tcp.confluent.io. IN SRV 10 50 389 ldap2.confluent.io.
_ldap._tcp.confluent.io. IN SRV 20 75 389 ldap3.confluent.io.
```

Which contains the SRV records with the priority (`ldap3` is higher in the list).

The broker is configured to talk to the BIND9 DNS server using `/etc/resolv.conf` (the docker-compose `dns` is working only with bridge mode, hence this workaround...):

```properties
nameserver 127.0.0.11
nameserver 172.28.1.1
options ndots:0
```

Where `127.0.0.11` is the generic docker DNS and `172.28.1.1` is BIND9 container.

The broker is then configured with:

```yml
KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL: "ldap:///dc=confluent,dc=io"
```

This is how it should be [set](https://docs.oracle.com/javase/8/docs/technotes/guides/jndi/jndi-ldap.html#URLs) with java in order to use DNS RSV records.
## Using DNS SRV Records With LDAP Over TLS

The attempt to make it worked has been done with [start-ldaps.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/ldap-authorizer-with-ldap-failover/start-ldaps.sh), but it is not working...

We're getting:

```log
[2021-12-15 10:37:34,812] ERROR LDAP search failed, search will be retried. Groups from the last successful search will continue to be applied until the configured retry timeout or the next successful search. (io.confluent.security.auth.provider.ldap.LdapGroupManager)
io.confluent.security.auth.provider.ldap.LdapException: LDAP context could not be created with provided configs
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.lambda$createLdapContext$0(LdapContextCreator.java:82)
        at java.base/java.security.AccessController.doPrivileged(Native Method)
        at java.base/javax.security.auth.Subject.doAs(Subject.java:361)
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.createLdapContext(LdapContextCreator.java:78)
        at io.confluent.security.auth.provider.ldap.LdapGroupManager.searchAndProcessResults(LdapGroupManager.java:347)
        at io.confluent.security.auth.provider.ldap.LdapGroupManager.start(LdapGroupManager.java:185)
        at io.confluent.security.auth.provider.ldap.LdapGroupProvider.configure(LdapGroupProvider.java:32)
        at io.confluent.security.authorizer.ConfluentAuthorizerConfig.lambda$createProviders$2(ConfluentAuthorizerConfig.java:167)
        at java.base/java.lang.Iterable.forEach(Iterable.java:75)
        at io.confluent.security.authorizer.ConfluentAuthorizerConfig.createProviders(ConfluentAuthorizerConfig.java:167)
        at io.confluent.security.authorizer.EmbeddedAuthorizer.configureServerInfo(EmbeddedAuthorizer.java:96)
        at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.configureServerInfo(ConfluentServerAuthorizer.java:85)
        at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.start(ConfluentServerAuthorizer.java:148)
        at kafka.server.KafkaServer.startup(KafkaServer.scala:553)
        at kafka.Kafka$.main(Kafka.scala:108)
        at kafka.Kafka.main(Kafka.scala)
Caused by: javax.naming.CommunicationException: ldap3.confluent.io.:636 [Root exception is javax.net.ssl.SSLHandshakeException: Illegal given domain name: ldap3.confluent.io.]
        at java.naming/com.sun.jndi.ldap.Connection.<init>(Connection.java:252)
        at java.naming/com.sun.jndi.ldap.LdapClient.<init>(LdapClient.java:137)
        at java.naming/com.sun.jndi.ldap.LdapClient.getInstance(LdapClient.java:1616)
        at java.naming/com.sun.jndi.ldap.LdapCtx.connect(LdapCtx.java:2847)
        at java.naming/com.sun.jndi.ldap.LdapCtx.<init>(LdapCtx.java:348)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getLdapCtxFromUrl(LdapCtxFactory.java:262)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURL(LdapCtxFactory.java:226)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURLs(LdapCtxFactory.java:280)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getLdapCtxInstance(LdapCtxFactory.java:185)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getInitialContext(LdapCtxFactory.java:115)
        at java.naming/javax.naming.spi.NamingManager.getInitialContext(NamingManager.java:730)
        at java.naming/javax.naming.InitialContext.getDefaultInitCtx(InitialContext.java:305)
        at java.naming/javax.naming.InitialContext.init(InitialContext.java:236)
        at java.naming/javax.naming.ldap.InitialLdapContext.<init>(InitialLdapContext.java:154)
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.lambda$createLdapContext$0(LdapContextCreator.java:80)
        ... 15 more
Caused by: javax.net.ssl.SSLHandshakeException: Illegal given domain name: ldap3.confluent.io.
        at java.base/sun.security.ssl.Alert.createSSLException(Alert.java:131)
        at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:349)
        at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:292)
        at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:287)
        at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:654)
        at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.onCertificate(CertificateMessage.java:473)
        at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.consume(CertificateMessage.java:369)
        at java.base/sun.security.ssl.SSLHandshake.consume(SSLHandshake.java:392)
        at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:443)
        at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:421)
        at java.base/sun.security.ssl.TransportContext.dispatch(TransportContext.java:182)
        at java.base/sun.security.ssl.SSLTransport.decode(SSLTransport.java:172)
        at java.base/sun.security.ssl.SSLSocketImpl.decode(SSLSocketImpl.java:1426)
        at java.base/sun.security.ssl.SSLSocketImpl.readHandshakeRecord(SSLSocketImpl.java:1336)
        at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:450)
        at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:421)
        at java.naming/com.sun.jndi.ldap.Connection.createSocket(Connection.java:364)
        at java.naming/com.sun.jndi.ldap.Connection.<init>(Connection.java:231)
        ... 29 more
Caused by: java.security.cert.CertificateException: Illegal given domain name: ldap3.confluent.io.
        at java.base/sun.security.util.HostnameChecker.matchDNS(HostnameChecker.java:193)
        at java.base/sun.security.util.HostnameChecker.match(HostnameChecker.java:103)
        at java.base/sun.security.ssl.X509TrustManagerImpl.checkIdentity(X509TrustManagerImpl.java:459)
        at java.base/sun.security.ssl.X509TrustManagerImpl.checkIdentity(X509TrustManagerImpl.java:429)
        at java.base/sun.security.ssl.X509TrustManagerImpl.checkTrusted(X509TrustManagerImpl.java:229)
        at java.base/sun.security.ssl.X509TrustManagerImpl.checkServerTrusted(X509TrustManagerImpl.java:129)
        at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:638)
        ... 42 more
Caused by: java.lang.IllegalArgumentException: Server name value of host_name cannot have the trailing dot
        at java.base/javax.net.ssl.SNIHostName.checkHostName(SNIHostName.java:319)
        at java.base/javax.net.ssl.SNIHostName.<init>(SNIHostName.java:108)
        at java.base/sun.security.util.HostnameChecker.matchDNS(HostnameChecker.java:191)
        ... 48 more
```

Unfortunately, it seems impossible to make it work, see this [link](https://serverfault.com/questions/1002895/ldaps-srv-resolution-not-working):

TL;DR: The LDAP spec doesn’t provide information on how to handle LDAPS with SRV records, so it’s non-standard.


## Testing different `KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL` values

With:

```yml
KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL: "ldap:///confluent.io"
```

```logs
[2021-12-15 14:09:15,516] ERROR LDAP search failed, search will be retried. Groups from the last successful search will continue to be applied until the configured retry timeout or the next successful search. (io.confluent.security.auth.provider.ldap.LdapGroupManager)
io.confluent.security.auth.provider.ldap.LdapException: LDAP context could not be created with provided configs
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.lambda$createLdapContext$0(LdapContextCreator.java:82)
        at java.base/java.security.AccessController.doPrivileged(Native Method)
        at java.base/javax.security.auth.Subject.doAs(Subject.java:361)
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.createLdapContext(LdapContextCreator.java:78)
        at io.confluent.security.auth.provider.ldap.LdapGroupManager.searchAndProcessResults(LdapGroupManager.java:347)
        at io.confluent.security.auth.provider.ldap.LdapGroupManager.start(LdapGroupManager.java:185)
        at io.confluent.security.auth.provider.ldap.LdapGroupProvider.configure(LdapGroupProvider.java:32)
        at io.confluent.security.authorizer.ConfluentAuthorizerConfig.lambda$createProviders$2(ConfluentAuthorizerConfig.java:167)
        at java.base/java.lang.Iterable.forEach(Iterable.java:75)
        at io.confluent.security.authorizer.ConfluentAuthorizerConfig.createProviders(ConfluentAuthorizerConfig.java:167)
        at io.confluent.security.authorizer.EmbeddedAuthorizer.configureServerInfo(EmbeddedAuthorizer.java:96)
        at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.configureServerInfo(ConfluentServerAuthorizer.java:85)
        at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.start(ConfluentServerAuthorizer.java:148)
        at kafka.server.KafkaServer.startup(KafkaServer.scala:553)
        at kafka.Kafka$.main(Kafka.scala:108)
        at kafka.Kafka.main(Kafka.scala)
Caused by: javax.naming.InvalidNameException: Invalid name: confluent.io
        at java.naming/javax.naming.ldap.Rfc2253Parser.doParse(Rfc2253Parser.java:111)
        at java.naming/javax.naming.ldap.Rfc2253Parser.parseDn(Rfc2253Parser.java:70)
        at java.naming/javax.naming.ldap.LdapName.parse(LdapName.java:785)
        at java.naming/javax.naming.ldap.LdapName.<init>(LdapName.java:123)
        at java.naming/com.sun.jndi.ldap.ServiceLocator.mapDnToDomainName(ServiceLocator.java:68)
        at java.naming/com.sun.jndi.ldap.DefaultLdapDnsProvider.lookupEndpoints(DefaultLdapDnsProvider.java:58)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURL(LdapCtxFactory.java:200)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURLs(LdapCtxFactory.java:280)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getLdapCtxInstance(LdapCtxFactory.java:185)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getInitialContext(LdapCtxFactory.java:115)
        at java.naming/javax.naming.spi.NamingManager.getInitialContext(NamingManager.java:730)
        at java.naming/javax.naming.InitialContext.getDefaultInitCtx(InitialContext.java:305)
        at java.naming/javax.naming.InitialContext.init(InitialContext.java:236)
        at java.naming/javax.naming.ldap.InitialLdapContext.<init>(InitialLdapContext.java:154)
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.lambda$createLdapContext$0(LdapContextCreator.java:80)
        ... 15 more
```

With only two `//`:

```yml
KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL: "ldap://confluent.io"
```

```logs
Caused by: javax.naming.CommunicationException: confluent.io:389 [Root exception is java.net.UnknownHostException: confluent.io]
        at java.naming/com.sun.jndi.ldap.Connection.<init>(Connection.java:252)
        at java.naming/com.sun.jndi.ldap.LdapClient.<init>(LdapClient.java:137)
        at java.naming/com.sun.jndi.ldap.LdapClient.getInstance(LdapClient.java:1616)
        at java.naming/com.sun.jndi.ldap.LdapCtx.connect(LdapCtx.java:2847)
        at java.naming/com.sun.jndi.ldap.LdapCtx.<init>(LdapCtx.java:348)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getLdapCtxFromUrl(LdapCtxFactory.java:262)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURL(LdapCtxFactory.java:226)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getUsingURLs(LdapCtxFactory.java:280)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getLdapCtxInstance(LdapCtxFactory.java:185)
        at java.naming/com.sun.jndi.ldap.LdapCtxFactory.getInitialContext(LdapCtxFactory.java:115)
        at java.naming/javax.naming.spi.NamingManager.getInitialContext(NamingManager.java:730)
        at java.naming/javax.naming.InitialContext.getDefaultInitCtx(InitialContext.java:305)
        at java.naming/javax.naming.InitialContext.init(InitialContext.java:236)
        at java.naming/javax.naming.ldap.InitialLdapContext.<init>(InitialLdapContext.java:154)
        at io.confluent.security.auth.provider.ldap.LdapContextCreator.lambda$createLdapContext$0(LdapContextCreator.java:80)
        ... 15 more
Caused by: java.net.UnknownHostException: confluent.io
        at java.base/java.net.AbstractPlainSocketImpl.connect(AbstractPlainSocketImpl.java:220)
        at java.base/java.net.SocksSocketImpl.connect(SocksSocketImpl.java:392)
        at java.base/java.net.Socket.connect(Socket.java:609)
        at java.naming/com.sun.jndi.ldap.Connection.createSocket(Connection.java:335)
        at java.naming/com.sun.jndi.ldap.Connection.<init>(Connection.java:231)
        ... 29 more
```

With:

```yml
KAFKA_LDAP_JAVA_NAMING_PROVIDER_URL: "ldap://ldap:389 ldap://ldap2:389 ldap://ldap3:389"
```

```logs
[2021-12-15 14:23:27,692] ERROR [KafkaServer id=1] Fatal error during KafkaServer startup. Prepare to shutdown (kafka.server.KafkaServer)
java.lang.IllegalArgumentException: Illegal character in authority at index 7: ldap://ldap:389 ldap://ldap2:389 ldap://ldap3:389
	at java.base/java.net.URI.create(URI.java:883)
	at io.confluent.security.auth.provider.ldap.LdapConfig.sslEnabled(LdapConfig.java:373)
	at io.confluent.security.auth.provider.ldap.LdapConfig.createLdapContextEnvironment(LdapConfig.java:390)
	at io.confluent.security.auth.provider.ldap.LdapConfig.<init>(LdapConfig.java:367)
	at io.confluent.security.auth.provider.ldap.LdapGroupProvider.configure(LdapGroupProvider.java:30)
	at io.confluent.security.authorizer.ConfluentAuthorizerConfig.lambda$createProviders$2(ConfluentAuthorizerConfig.java:167)
	at java.base/java.lang.Iterable.forEach(Iterable.java:75)
	at io.confluent.security.authorizer.ConfluentAuthorizerConfig.createProviders(ConfluentAuthorizerConfig.java:167)
	at io.confluent.security.authorizer.EmbeddedAuthorizer.configureServerInfo(EmbeddedAuthorizer.java:96)
	at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.configureServerInfo(ConfluentServerAuthorizer.java:85)
	at io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer.start(ConfluentServerAuthorizer.java:148)
	at kafka.server.KafkaServer.startup(KafkaServer.scala:553)
	at kafka.Kafka$.main(Kafka.scala:108)
	at kafka.Kafka.main(Kafka.scala)
Caused by: java.net.URISyntaxException: Illegal character in authority at index 7: ldap://ldap:389 ldap://ldap2:389 ldap://ldap3:389
	at java.base/java.net.URI$Parser.fail(URI.java:2913)
	at java.base/java.net.URI$Parser.parseAuthority(URI.java:3247)
	at java.base/java.net.URI$Parser.parseHierarchical(URI.java:3158)
	at java.base/java.net.URI$Parser.parse(URI.java:3114)
	at java.base/java.net.URI.<init>(URI.java:600)
	at java.base/java.net.URI.create(URI.java:881)
	... 13 more
```
