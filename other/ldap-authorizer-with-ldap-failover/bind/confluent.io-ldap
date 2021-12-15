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
