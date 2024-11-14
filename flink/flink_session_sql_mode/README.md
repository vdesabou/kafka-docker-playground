# Apache Flink in Session Mode with SQL Client using Docker Compose

This setup runs Apache Flink in **Session Mode** with the **SQL Client**.

## How to attach to SQL client
```
docker attach sql-client
```
When quitting out of the SQL client, the container will stop working. If you wish to restart the SQL Client, simply run:
```
docker-compose start sql-client
```

## How to Start

```bash
./start.sh
```

## How to Stop

```bash
./stop.sh
```