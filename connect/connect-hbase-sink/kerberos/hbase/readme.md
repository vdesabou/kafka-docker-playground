# Kerberized Hbase

This image contains `hadoop`, `hbase` and `zookeeper`.

`Dockerfile.base` is image with installed pure hadoop, hbase and zookeeper.

`Dockerfile` copies configurations and starts cluster. Also, the `_HOST` is replaced by current hostname on startup.
