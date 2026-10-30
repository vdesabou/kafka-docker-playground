# ♨️ Connectors and JDKs

Add other connector plugins or SMTs to an example, or replace the JDK of a container image. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> The [🍪 deep dive on containers](/deep-dive-container-lifecycle.md) explains restart vs recreate, environment variables and the JDK.

## 🧙 How to install other connectors

Simplest option is to create a reproduction model with `playground repro bootstrap` [command](/playground%20repro%20bootstrap) and then select "🔌 Add connector plugin" (you can call it multiple times to add multiple connector plugins/SMT) 

<img width="774" height="285" alt="CleanShot 2026-01-13 at 14 42 46" src="https://github.com/user-attachments/assets/e1489b80-8d01-48c2-906a-b359230104e8" />

it has interactive selection from confluent hub:

<img width="966" height="512" alt="CleanShot 2026-01-13 at 14 43 09" src="https://github.com/user-attachments/assets/a36e909a-4104-47c7-9637-31a902976141" />

It will automatically add the plugin(s) to the list of `CONNECT_PLUGIN_PATH`:

Example with S3 source and S3 sink:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-kafka-connect-s3
```

Example with [confluentinc/connect-transforms](https://www.confluent.io/hub/confluentinc/connect-transforms) SMT:

```yml
services:
  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-s3-source,/usr/share/confluent-hub-components/confluentinc-connect-transforms
```

It can also be done non-interactively with `--connector-plugin` (repeatable):

```bash
playground repro bootstrap -f s3-sink<tab> --description "s3 sink with transforms" --connector-plugin confluentinc/connect-transforms
```

> [!TIP]
> You can also specify versions when specifying multiple connector/SMT, see [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%94%97-for-connectors).

## ♨️ Using specific JDK

Some issues depend on the Java version or vendor (TLS protocols and cipher suites, a JVM bug, a library that needs a more recent Java, a difference seen only with the customer's JDK). To reproduce them, you can replace the JDK installed in a container image (connect, broker, control-center…) with another version or vendor.

Here are some examples:

### 🌀 Azul Zulu JDK

Just use [playground container change-jdk](/playground%20container%20change-jdk) CLI command !

Example:

```bash
$ playground container change-jdk --version 21 --container control-center 
17:03:25 ℹ️ 🤎 Installing Azul JDK 21 on container control-center /usr/lib/jvm/java-11-zulu-openjdk/bin/java
17:03:25 ℹ️ Executing command as root in container control-center with bash
Last metadata expiration check: 0:26:16 ago on Fri May 24 14:37:10 2024.
zulu-repo-1.0.0-1.noarch.rpm                    4.4 kB/s | 3.0 kB     00:00    
Package zulu-repo-1.0.0-1.noarch is already installed.
Dependencies resolved.
Nothing to do.
Complete!
Last metadata expiration check: 0:26:17 ago on Fri May 24 14:37:10 2024.
Dependencies resolved.
================================================================================
 Package                     Architecture Version       Repository         Size
================================================================================
Installing:
 zulu21-jdk                  aarch64      21.0.3-1      zulu-openjdk      4.3 k
Installing dependencies:
 zulu21-ca-doc               aarch64      21.0.3-1      zulu-openjdk      232 k
 zulu21-ca-jdk               aarch64      21.0.3-1      zulu-openjdk       23 k
 zulu21-ca-jdk-headless      aarch64      21.0.3-1      zulu-openjdk       81 M
 zulu21-ca-jre               aarch64      21.0.3-1      zulu-openjdk      354 k
 zulu21-ca-jre-headless      aarch64      21.0.3-1      zulu-openjdk       47 M
 zulu21-doc                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jdk-headless         aarch64      21.0.3-1      zulu-openjdk      4.3 k
 zulu21-jre                  aarch64      21.0.3-1      zulu-openjdk      4.2 k
 zulu21-jre-headless         aarch64      21.0.3-1      zulu-openjdk      4.2 k

Transaction Summary
================================================================================
Install  10 Packages

Total download size: 128 M
Installed size: 295 M
Downloading Packages:
(1/10): zulu21-ca-jdk-21.0.3-1.aarch64.rpm      180 kB/s |  23 kB     00:00    
(2/10): zulu21-ca-doc-21.0.3-1.aarch64.rpm      1.2 MB/s | 232 kB     00:00    
(3/10): zulu21-ca-jre-21.0.3-1.aarch64.rpm      1.5 MB/s | 354 kB     00:00    
(4/10): zulu21-doc-21.0.3-1.aarch64.rpm          36 kB/s | 4.2 kB     00:00    
(5/10): zulu21-jdk-21.0.3-1.aarch64.rpm          66 kB/s | 4.3 kB     00:00    
(6/10): zulu21-jdk-headless-21.0.3-1.aarch64.rp  36 kB/s | 4.3 kB     00:00    
(7/10): zulu21-jre-21.0.3-1.aarch64.rpm          76 kB/s | 4.2 kB     00:00    
(8/10): zulu21-jre-headless-21.0.3-1.aarch64.rp 100 kB/s | 4.2 kB     00:00    
(9/10): zulu21-ca-jre-headless-21.0.3-1.aarch64 3.2 MB/s |  47 MB     00:14    
(10/10): zulu21-ca-jdk-headless-21.0.3-1.aarch6 5.3 MB/s |  81 MB     00:15    
--------------------------------------------------------------------------------
Total                                           8.4 MB/s | 128 MB     00:15     
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64                1/1 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                         1/1 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                   1/1 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                            1/1 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                            1/1 
  Preparing        :                                                        1/1 
  Installing       : zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64               1/10 
  Installing       : zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64               2/10 
  Installing       : zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                        3/10 
  Installing       : zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                  4/10 
  Installing       : zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                        5/10 
  Installing       : zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                        6/10 
  Installing       : zulu21-doc-21.0.3-1.aarch64                           7/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                           7/10 
  Installing       : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Installing       : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                           9/10 
  Installing       : zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-ca-jre-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jdk-headless-21.0.3-1.aarch64              10/10 
  Running scriptlet: zulu21-ca-jre-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-jre-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-ca-doc-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-ca-jdk-21.0.3-1.aarch64                       10/10 
  Running scriptlet: zulu21-doc-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-headless-21.0.3-1.aarch64                 10/10 
  Running scriptlet: zulu21-jre-21.0.3-1.aarch64                          10/10 
  Running scriptlet: zulu21-jdk-21.0.3-1.aarch64                          10/10 
  Verifying        : zulu21-ca-doc-21.0.3-1.aarch64                        1/10 
  Verifying        : zulu21-ca-jdk-21.0.3-1.aarch64                        2/10 
  Verifying        : zulu21-ca-jdk-headless-21.0.3-1.aarch64               3/10 
  Verifying        : zulu21-ca-jre-21.0.3-1.aarch64                        4/10 
  Verifying        : zulu21-ca-jre-headless-21.0.3-1.aarch64               5/10 
  Verifying        : zulu21-doc-21.0.3-1.aarch64                           6/10 
  Verifying        : zulu21-jdk-21.0.3-1.aarch64                           7/10 
  Verifying        : zulu21-jdk-headless-21.0.3-1.aarch64                  8/10 
  Verifying        : zulu21-jre-21.0.3-1.aarch64                           9/10 
  Verifying        : zulu21-jre-headless-21.0.3-1.aarch64                 10/10 

Installed:
  zulu21-ca-doc-21.0.3-1.aarch64           zulu21-ca-jdk-21.0.3-1.aarch64       
  zulu21-ca-jdk-headless-21.0.3-1.aarch64  zulu21-ca-jre-21.0.3-1.aarch64       
  zulu21-ca-jre-headless-21.0.3-1.aarch64  zulu21-doc-21.0.3-1.aarch64          
  zulu21-jdk-21.0.3-1.aarch64              zulu21-jdk-headless-21.0.3-1.aarch64 
  zulu21-jre-21.0.3-1.aarch64              zulu21-jre-headless-21.0.3-1.aarch64 

Complete!
17:03:54 ℹ️ Executing command as root in container control-center with bash
17:03:54 ℹ️ Restarting docker container control-center
control-center
17:04:02 ℹ️ Executing command in container control-center with bash
openjdk version "21.0.3" 2024-04-16 LTS
OpenJDK Runtime Environment Zulu21.34+19-CA (build 21.0.3+9-LTS)
OpenJDK 64-Bit Server VM Zulu21.34+19-CA (build 21.0.3+9-LTS, mixed mode, sharing)
```

### ⭕️ Oracle JDK

Here are the steps to follow:

1. Get the Oracle JDK `.rpm` version link you want to install from the [website](https://www.oracle.com/java/technologies/downloads/). In our example, that will be `jdk-21_linux-x64_bin.rpm`

> [!NOTE]
> CP 8.x requires Java 17 or later, so pick a JDK 17+ build. CP images are based on UBI minimal, which ships `microdnf` and not `yum`: the `Dockerfile` below installs `yum` first.

2. Add this in your `docker-compose` file:

```yml
  connect:
    build:
      context: ../../connect/connect-filestream-sink/
      args:
        CP_CONNECT_IMAGE: ${CP_CONNECT_IMAGE}
        CP_CONNECT_TAG: ${CP_CONNECT_TAG}
```
> [!WARNING]
> Make sure to update `context` above with the right path.

3. Create a `Dockerfile` file in `context` directory above (`../../connect/connect-filestream-sink/`).

```dockerfile
ARG CP_CONNECT_IMAGE
ARG CP_CONNECT_TAG
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
COPY jdk-21_linux-x64_bin.rpm /tmp/
USER root
RUN if command -v microdnf >/dev/null 2>&1; then microdnf -y install yum; fi \
 && yum -y install /tmp/jdk-21_linux-x64_bin.rpm \
 && alternatives --set java /usr/lib/jvm/jdk-21-oracle-x64/bin/java \
 && rm /tmp/jdk-21_linux-x64_bin.rpm
USER appuser
```

> [!WARNING]
> Make sure to update `alternatives --set java` above with the right path.

4. Verify the correct JDK version is installed once your test is started:

```bash
playground container exec -c connect --command "java -version"
```
