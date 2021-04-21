# Control Center in "Read-Only" mode

## Objective

Quickly test [UI HTTP Basic Authentication]([https://docs.confluent.io/current/connect/kafka-connect-sftp/sink-connector/index.html#quick-start) to setup Control Center in read-only mode.

Configuration setup:

```yml
  control-center:
    volumes:
      - ../../other/control-center-readonly-mode/login.properties:/tmp/login.properties
      - ../../other/control-center-readonly-mode/propertyfile.jaas:/tmp/propertyfile.jaas
    environment:
      CONTROL_CENTER_REST_AUTHENTICATION_ROLES: Administrators,Restricted
      CONTROL_CENTER_AUTH_RESTRICTED_ROLES: Restricted
      CONTROL_CENTER_REST_AUTHENTICATION_METHOD: BASIC
      CONTROL_CENTER_REST_AUTHENTICATION_REALM: c3
      CONTROL_CENTER_OPTS: -Djava.security.auth.login.config=/tmp/propertyfile.jaas
```

login.properties:

```
admin: admin_pw,Administrators
monitor: monitor,Restricted
disallowed: no_access
```

propertyfile.jaas:

```
c3 {
org.eclipse.jetty.jaas.spi.PropertyFileLoginModule required
file="/tmp/login.properties";
};
```

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

In order to login into Control Center, you will be now prompted with login/password:

`admin/admin_pw` for Admin account
`monitor/monitor` for readonly account

## Issue with other components configured with Basic Authentication

If another component is configured to use Basic Authentication (Connect or ksqlDB for example), Control Center will use the username/password defined for current user, therefore it should also be defined for other components.

There is an example with Connect, which is configured with Basic Authentication:

```yml
  connect:
    volumes:
        - ../../other/control-center-readonly-mode/connect.jaas:/tmp/connect.jaas
        - ../../other/control-center-readonly-mode/connect.password:/tmp/connect.password
    environment:
      CONNECT_REST_EXTENSION_CLASSES: org.apache.kafka.connect.rest.basic.auth.extension.BasicAuthSecurityRestExtension
      KAFKA_OPTS: -Djava.security.auth.login.config=/tmp/connect.jaas
```

With `connect.jaas`:

```
KafkaConnect {
    org.apache.kafka.connect.rest.basic.auth.extension.PropertyFileLoginModule required
    file="/tmp/connect.password";
};
```

And `connect.password`:

```
connectuser: connectpassword
admin: admin_pw
```

If admin/admin_pw is not defined at connect level, Control-Center will display an error while connecting to the connect cluster.