if [ -d $root_folder/.ccloud ]
then
    log "🧼 removing folder $root_folder/.ccloud"
    rm -rf $root_folder/.ccloud
fi

playground state del ccloud.ENVIRONMENT
playground state del ccloud.CLUSTER_NAME
playground state del ccloud.CLUSTER_CLOUD
playground state del ccloud.CLUSTER_REGION
playground state del ccloud.CLUSTER_CREDS
playground state del ccloud.SCHEMA_REGISTRY_CREDS
playground state del ccloud.suggest_use_previous_example_ccloud
playground state del ccloud.FLINK_COMPUTE_POOL
