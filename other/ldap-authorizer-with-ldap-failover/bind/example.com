$TTL 900
@     IN  SOA example.com. postmaster.example.com. (
        2020062101      ; Serial Number
        1800            ; Refresh
        900             ; Retry
        1209600         ; expire
        900             ; minimum
        )
;
      IN    NS  example.com.
      IN    A   1.2.3.4

_ldap._tcp.example.com. IN SRV 10 50 389 ldap.example.com.
_ldap._tcp.example.com. IN SRV 10 50 389 ldap2.example.com.
_ldap._tcp.example.com. IN SRV 20 75 389 ldap3.example.com.
