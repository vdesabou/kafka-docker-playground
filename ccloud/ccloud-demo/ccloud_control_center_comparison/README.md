# Differences between Confluent Cloud UI and local Control Center connected to Confluent Cloud

**Notes**:

* if the cluster is [VPC peered](https://docs.confluent.io/current/cloud/vpc.html), we assume that [Configuring Access to the UI Dashboard](https://docs.confluent.io/current/cloud/vpc.html#configuring-access-to-the-ui-dashboard) has been setup, otherwise Topics, Consumers and KSQL tabs will be empty and show a banner to setup proxy.

* Cloud UI is evolving a lot, the screenshots shown below were accurate only at the time they were published, i.e Nov, 19th 2019.


|   |  Confluent Cloud UI | Control Center UI |
|---|---|---|
|Landing Page| ![Landing Page](../images/1.jpg)  | ![Landing Page](../images/2.jpg)  |
|Brokers tab| not available  | ![Brokers](../images/3.jpg) <br> Warning is [expected](https://docs.confluent.io/current/cloud/connect/c3-cloud-config.html#limitations) as Confluent Cloud does not provide the instrumentation from Confluent Metrics Reporter outside of the Confluent Cloud. |
|Topics tab| ![Topics tab](../images/4.jpg)  | ![Topics tab](../images/5.jpg)  |
|Topic overview| not available | ![Topic overview](../images/12.jpg)  |
|Topic configuration| ![Topic configuration](../images/6.jpg)  | ![Topic configuration](../images/7.jpg)  |
|Topic messages| ![Topic messages](../images/8.jpg)  | ![Topic messages](../images/9.jpg)  |
|Topic schema <br>(using Confluent Cloud Schema Registry)| ![Topic schema](../images/10.jpg)  | ![Topic schema](../images/11.jpg)  |
|Connectors tab| ![Connectors tab](../images/13.jpg) <br> This is only showing _managed_ connectors | ![Connectors tab](../images/14.jpg) <br> This is showing _local_ Connect clusters |
|Connectors tab (2)| ![Connectors tab](../images/15.jpg) <br> This is only showing _managed_ connectors | ![Connectors tab](../images/16.jpg) <br> This is showing _local_ connectots |
|KSQL tab| ![KSQL tab](../images/17.jpg) <br> This is only showing _managed_ KSQL Cloud (in Preview) | ![KSQL tab](../images/18.jpg) <br> This is showing _local_ KSQL clusters |
|Consumers tab| ![Consumers tab](../images/19.jpg)  | ![Consumers tab](../images/20.jpg)  |
|Consumer Group /<br> Consumer lag| ![Consumer group](../images/21.jpg)  | ![Consumer lag](../images/22.jpg)  |
|Consumer Group /<br> Consumption| not available  | ![Consumer Consumption](../images/23.jpg)  |
|Consumer Group /<br> Alerts| not available  | ![Consumer Alerts](../images/24.jpg)  |
|Cluster settings tab| ![Cluster settings tab](../images/25.jpg)  | ![Cluster settings tab](../images/26.jpg)  |
|Cluster settings tab /<br> API access| ![Cluster settings tab](../images/29.jpg)  | not applicable |
|CLI @ client configuration tab| ![CLI @ client configuration tab](../images/27.jpg)  | not applicable  |
|CLI @ client configuration tab (2)| ![CLI @ client configuration tab](../images/27.jpg)  | not applicable  |
|Schema Registry tab| ![Schema Registry](../images/30.jpg)  | not applicable <br>(this is only for Confluent Cloud Schema Registry) |
|Schema Registry tab /<br> API access| ![Schema Registry](../images/31.jpg)  | not applicable <br>(this is only for Confluent Cloud Schema Registry)  |
|Schema Registry tab /<br> Allowed Usage| ![Schema Registry](../images/32.jpg)  | not applicable <br>(this is only for Confluent Cloud Schema Registry)  |