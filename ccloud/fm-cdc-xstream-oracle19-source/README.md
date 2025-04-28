# Fully Managed Oracle XStream CDC Source (Oracle 19c) Source connector

## Objective

Quickly test [Fully Managed Oracle XStream CDC Source Connector](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/cc-oracle-xstream-cdc-source-features.html) with Oracle 19c.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip`from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`


Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:19.3.0-ee`. It takes about 10 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

