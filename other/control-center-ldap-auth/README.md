# Configuring Control Center with LDAP authentication

## Objective

Quickly test [Configuring Control Center with LDAP authentication]([https://support.confluent.io/hc/en-us/articles/115003890503-Configuring-Control-Center-with-LDAP-authentication) to setup Control Center in read-only mode.

Configuration setup:

```yml
  control-center:
    volumes:
      - ../../other/control-center-readonly-mode/propertyfile.jaas:/tmp/propertyfile.jaas
    environment:
      CONTROL_CENTER_REST_AUTHENTICATION_ROLES: c3users,readonlyusers
      CONTROL_CENTER_AUTH_RESTRICTED_ROLES: readonlyusers
      CONTROL_CENTER_REST_AUTHENTICATION_METHOD: BASIC
      CONTROL_CENTER_REST_AUTHENTICATION_REALM: c3
      CONTROL_CENTER_OPTS: -Djava.security.auth.login.config=/tmp/propertyfile.jaas
```

propertyfile.jaas:

```
c3 {
  org.eclipse.jetty.jaas.spi.LdapLoginModule required

  useLdaps="false"
  contextFactory="com.sun.jndi.ldap.LdapCtxFactory"
  hostname="ldap"
  port="389"
  bindDn="cn=admin,dc=confluent,dc=io"
  bindPassword="password"
  authenticationMethod="simple"
  forceBindingLogin="false"
  userBaseDn="ou=users,dc=confluent,dc=io"
  userRdnAttribute="uid"
  userIdAttribute="cn"
  userPasswordAttribute="userPassword"
  userObjectClass="inetOrgPerson"
  roleBaseDn="ou=groups,dc=confluent,dc=io"
  roleNameAttribute="cn"
  roleMemberAttribute="memberuid"
  roleObjectClass="posixGroup";
};
```

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])

In order to login into Control Center, you will be now prompted with login/password:

`alice/alice-secret` has full access, because it is in `c3users` group
`barnie/barnie-secret` has full access, because it is in `c3users` group
`charlie/charlie-secret` has no access, because it is **not** in `c3users` group
`john/john-secret` has readonly access, because it is in `readonlyusers` group



