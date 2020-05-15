# Differences between Confluent Cloud UI and local Control Center connected to Confluent Cloud

**Notes**:

* if the cluster is [VPC peered](https://docs.confluent.io/current/cloud/vpc.html), we assume that [Configuring Access to the UI Dashboard](https://docs.confluent.io/current/cloud/vpc.html#configuring-access-to-the-ui-dashboard) has been setup, otherwise Topics, Consumers and KSQL tabs will be empty and show a banner to setup proxy.

* Cloud UI is evolving a lot, the screenshots shown below were accurate only at the time they were published, i.e Nov, 19th 2019.


|   |  Confluent Cloud UI | Control Center UI |
|---|---|---|
|Cluster Overview| ![Cluster Overview](../images/cluster_ccloud.png)  | ![Cluster Overview](../images/cluster_c3.png)  |
|Brokers tab| not available  | ![Brokers](../images/brokers_c3.png) <br> Warning is [expected](https://docs.confluent.io/current/cloud/connect/c3-cloud-config.html#limitations) as Confluent Cloud does not provide the instrumentation from Confluent Metrics Reporter outside of the Confluent Cloud. |
|Data Flow tab| ![Data flow tab](../images/data_flow_cloud.png)| not available |
|Topics tab| ![Topics tab](../images/topics_cloud.png)  | ![Topics tab](../images/topics_c3.png)  |
|Topic overview| ![Topic overview](../images/topic_overview_cloud.png) | ![Topic overview](../images/topic_overview_c3.png)  |
|Topic configuration| ![Topic configuration](../images/topic_config_cloud.png)  | ![Topic configuration](../images/topic_config_c3.png)  |
|Topic messages| ![Topic messages](../images/topic_messages_cloud.png)  | ![Topic messages](../images/topic_messages_c3.png)  |
|Topic schema <br>(using Confluent Cloud Schema Registry)| ![Topic schema](../images/topic_schema_cloud.png)  | ![Topic schema](../images/topic_schema_c3.png)  |
|Connectors tab| ![Connectors tab](../images/connectors_cloud.png) <br> This is only showing _managed_ connectors | ![Connectors tab](../images/connectors_c3.png) <br> This is showing _local_ Connect clusters |
|KSQL tab| ![KSQL tab](../images/ksql_cloud.png) <br> This is only showing _managed_ KSQL Cloud (in Preview) | ![KSQL tab](../images/ksql_c3.png) <br> This is showing _local_ KSQL clusters |
|Consumers tab| ![Consumers tab](../images/consumers_cloud.png)  | ![Consumers tab](../images/consumers_c3.png)  |
|Consumer Group /<br> Consumer lag| ![Consumer group](../images/consumer_group_cloud.png)  | ![Consumer lag](../images/consumer_group_c3.png)  |
|Consumer Group /<br> Consumption| not available  | ![Consumer Consumption](../images/consumption_c3.png)  |
|Consumer Group /<br> Alerts| not available  | ![Consumer Alerts](../images/consumer_group_alerts.png)  |
|Cluster API Keys| ![API Keys](../images/api_keys_cloud.png)  | not available |
|Cluster settings tab| ![Cluster settings tab](../images/cluster_settings_cloud.png)  | ![Cluster settings tab](../images/cluster_settings_c3.png)  |
|Cluster settings tab /<br> capacity | ![Cluster settings tab](../images/cluster_settings_capacity_cloud.png)  | not applicable |
|Tools & client configuration tab| ![CLI @ client configuration tab](../images/tools_cloud.png)  | not applicable  |
|Tools & client configuration tab (2)| ![CLI @ client configuration tab](../images/tools_cloud_1.png)  | not applicable  |
|Tools & client configuration tab (3)| ![CLI @ client configuration tab](../images/tools_cloud_2.png)  | not applicable  |
|Schema Registry tab| ![Schema Registry](../images/sr_cloud_1.png)  | not applicable <br>(this is only for Confluent Cloud Schema Registry) |
|Schema Registry tab /<br> API access| ![Schema Registry](../images/sr_cloud_2.png)  | not applicable <br>(this is only for Confluent Cloud Schema Registry)  |
|Schema Registry tab /<br> Allowed Usage| ![Schema Registry](../images/sr_cloud_3.png)  | not applicable <br>(this is only for Confluent Cloud Schema Registry)  |