# Write logs to files

## Using custom log4j.properties

To run:

```
$ ./start-custom-log4j.sh
```

Example using `docker-compose` on how to write logs to files by providing custom `log4j.properties` files.

The general idea is to mount as volume the directory where you want to store the logs and provide a log4j properties file that write files to this directory:

```yml
  zookeeper:
    volumes:
      - ../../other/write-logs-to-files/zookeeper/log4j-rolling.properties:/opt/zookeeper/log4j-rolling.properties
      - ../../other/write-logs-to-files/zookeeper/logs:/var/log/zookeeper/
    environment:
      KAFKA_LOG4J_OPTS: "-Dlog4j.configuration=file:/opt/zookeeper/log4j-rolling.properties"
```

The path of the log4j properties file is done by using environment variable, for zookeeper it is `KAFKA_LOG4J_OPTS`

In summary, we have:

| Component  | Environment variable  |
|---|---|
| zookeeper  |  KAFKA_LOG4J_OPTS |
| broker     |  KAFKA_LOG4J_OPTS |
| schema-registry  |  SCHEMA_REGISTRY_LOG4J_OPTS |
| connect    |  KAFKA_LOG4J_OPTS |
| ksql-server  |  KSQL_LOG4J_OPTS |
| control-center  |  CONTROL_CENTER_LOG4J_OPTS |

**WARNING:** By doing like this, you lose the possibily configure logging using environment variables as explained [here](https://docs.confluent.io/current/installation/docker/operations/logging.html#log4j-log-levels)


## Using template log4j.properties

To run:

```
$ ./start-template-log4j.sh
```

This is explained [here](https://docs.confluent.io/current/installation/docker/development.html#log-to-external-volumes)

In Docker images, there is a template available in `/etc/confluent/docker/log4j.properties.template` that you can tweak to add your own appenders, in order to write to files for example.

See examples:

| Component  | Environment variable  |
|---|---|
| zookeeper  |  [zookeeper/log4j.template.properties](zookeeper/log4j.template.properties) |
| broker     |  [broker/log4j.template.properties](broker/log4j.template.properties) |
| schema-registry  |  [schema-registry/log4j.template.properties](schema-registry/log4j.template.properties) |
| connect    |  [connect/log4j.template.properties](connect/log4j.template.properties) |
| ksql-server  |  [ksql-server/log4j.template.properties](ksql-server/log4j.template.properties) |
| control-center  |  [control-center/log4j.template.properties](control-center/log4j.template.properties) |

By using those modified templates, you can still configure logging using environment variables as explained [here](https://docs.confluent.io/current/installation/docker/operations/logging.html#log4j-log-levels)

Example:

```yml
  connect:
    volumes:
      - ../../other/write-logs-to-files/connect/log4j.template.properties:/etc/confluent/docker/log4j.properties.template
      - ../../other/write-logs-to-files/connect/logs:/var/log/connect/
    environment:
      CONNECT_LOG4J_ROOT_LOGLEVEL: "TRACE"
      CONNECT_LOG4J_LOGGERS: "org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR"
      # CONNECT_LOG4J_APPENDER_STDOUT_LAYOUT_CONVERSIONPATTERN: "[%d] %p %m (%c)%n'"
```

### Results

You should see logs in Docker container in `/var/log/<component>` and also in mounted volumes as following:

![Logs](Screenshot1.png)


