get_ksqldb_url_and_security || exit 0
ksqldb_rest_statement "SHOW STREAMS; SHOW TABLES;" 2>/dev/null | jq -r '.[] | (.streams // .tables // [])[] | .name' 2>/dev/null
