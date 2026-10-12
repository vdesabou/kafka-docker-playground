# sourced by environment/rbac-sasl-plain/start.sh before schema-registry starts
log "Creating ACL topic role binding for Schema Registry"
playground rbac role-binding create --principal User:schemaregistryUser --role ResourceOwner --resource Topic:_schemas_acl
