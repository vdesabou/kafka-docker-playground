#!/bin/bash

#!/bin/bash

[[ "TRACE" ]] && set -x

: ${REALM:=NODE.DC1.CONSUL}
: ${DOMAIN_REALM:=node.dc1.consul}
: ${KERB_MASTER_KEY:=masterkey}
: ${KERB_ADMIN_USER:=admin}
: ${KERB_ADMIN_PASS:=admin}
: ${SEARCH_DOMAINS:=search.consul node.dc1.consul}

fix_nameserver() {
  cat>/etc/resolv.conf<<EOF
nameserver $NAMESERVER_IP
search $SEARCH_DOMAINS
EOF
}

fix_hostname() {
  sed -i "/^hosts:/ s/ *files dns/ dns files/" /etc/nsswitch.conf
}

create_config() {
  : ${KDC_ADDRESS:=$(hostname -f)}

  cat>/etc/krb5.conf<<EOF
[logging]
 default = FILE:/var/log/kerberos/krb5libs.log
 kdc = FILE:/var/log/kerberos/krb5kdc.log
 admin_server = FILE:/var/log/kerberos/kadmind.log
[libdefaults]
 default_realm = $REALM
 dns_lookup_realm = false
 dns_lookup_kdc = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
[realms]
 $REALM = {
  kdc = kerberos.kerberos-demo.local
  admin_server = kerberos.kerberos-demo.local
 }
[domain_realm]
 .$DOMAIN_REALM = $REALM
 $DOMAIN_REALM = $REALM
EOF
}

create_db() {
  /usr/sbin/kdb5_util -P $KERB_MASTER_KEY -r $REALM create -s
}

start_kdc() {
  mkdir -p /var/log/kerberos

  /etc/rc.d/init.d/krb5kdc start
  /etc/rc.d/init.d/kadmin start

  chkconfig krb5kdc on
  chkconfig kadmin on
}

restart_kdc() {
  /etc/rc.d/init.d/krb5kdc restart
  /etc/rc.d/init.d/kadmin restart
}

create_admin_user() {
  kadmin.local -q "addprinc -pw $KERB_ADMIN_PASS $KERB_ADMIN_USER/admin"
  echo "*/admin@$REALM *" > /var/kerberos/krb5kdc/kadm5.acl
}

create_hackolade_user() {
	mkdir -p /opt/keytabs

	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -pw ${KERBEROS_ROOT_USER_PASSWORD} root@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey nn/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey dn/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey HTTP/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey jhs/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey yarn/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey rm/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey nm/hbase.kerberos-demo.local@${REALM}"

	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey zookeeper/hbase.kerberos-demo.local@${REALM}"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -randkey hbase/hbase.kerberos-demo.local@${REALM}"

	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/nn.service.keytab nn/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/dn.service.keytab dn/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/spnego.service.keytab HTTP/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/jhs.service.keytab jhs/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/yarn.service.keytab yarn/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/rm.service.keytab rm/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/nm.service.keytab nm/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/zookeeper.keytab zookeeper/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "xst -k /opt/keytabs/hbase.keytab hbase/hbase.kerberos-demo.local"
	kadmin -p $KERB_ADMIN_USER/admin -w $KERB_ADMIN_PASS -q "addprinc -pw ${CLIENT_PASS} ${CLIENT_USER}@${REALM}"

	chmod 777 -R /opt/keytabs
}

main() {
  fix_nameserver
  fix_hostname

  if [ ! -f /kerberos_initialized ]; then
    create_config
    create_db
    create_admin_user
    start_kdc

    touch /kerberos_initialized
  fi

  if [ ! -f /var/kerberos/krb5kdc/principal ]; then
    while true; do sleep 1000; done
  else
    start_kdc
    create_hackolade_user
    tail -F /var/log/kerberos/krb5kdc.log
  fi
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
