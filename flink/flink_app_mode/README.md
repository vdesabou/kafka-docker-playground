# Apache Flink in Application Mode with Docker Compose

This setup runs Apache Flink in [**Application Mode**](https://nightlies.apache.org/flink/flink-docs-release-1.20/docs/deployment/resource-providers/standalone/docker/#application-mode-1) using Docker Compose. If you wish to deploy a application, ensure to specify environment variable:

```
export FLINK_JAR_PATH=/path/to/my/file.jar
```

## How to Start

```bash
./start.sh
```

## How to Stop

```bash
./stop.sh
```