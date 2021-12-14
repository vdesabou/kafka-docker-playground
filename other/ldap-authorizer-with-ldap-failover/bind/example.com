$TTL    604800
@       IN      SOA     bind.example.com. root.example.com. (
                  3       ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800 )   ; Negative Cache TTL
;
; name servers - NS records
     IN      NS      bind.example.com.

; name servers - A records
bind.example.com.          IN      A      172.28.1.1
ldap.example.com.          IN      A      172.28.1.2
ldap2.example.com.         IN      A      172.28.1.7
ldap3.example.com.         IN      A      172.28.1.8

_ldap._tcp.example.com. IN SRV 10 50 389 ldap.example.com.
_ldap._tcp.example.com. IN SRV 10 50 389 ldap2.example.com.
_ldap._tcp.example.com. IN SRV 20 75 389 ldap3.example.com.
