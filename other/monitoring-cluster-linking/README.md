`kafka.server:type=cluster-link-metrics,name=failed-mirror-partition-count,link-name={linkName}`
Seems not existing
https://github.com/confluentinc/ce-kafka/pull/3431/files
but this exists kafka_server_link_clusterlinkfetchermanager_failedpartitionscount
https://github.com/confluentinc/ce-kafka/blob/db0c41aa38090b70f63334d71572990c3c594f7d/core/src/main/scala/kafka/server/link/ClusterLinkFetcherManager.scala#L39

kafka.server:type=cluster-link-metrics,mode=destination,state=unavailable,link-name=link-us-to-europe

kafka.server:type=cluster-link-metrics,link-name=link-us-to-europe topic mirror-topic-lag
vs 
ConsumerLag

kafka.server<type=cluster-link-metrics, link-name=link-us-to-europe><>link-source-unavailable-rate
kafka_server_cluster_link_metrics_link_source_unavailable_total
vs
kafka_server_cluster_link_metrics_link_count{env="destination", instance="broker-europe:1234", job="kafka", link_name="link-us-to-europe", mode="destination", state="unavailable"}
https://github.com/confluentinc/ce-kafka/pull/9316


availability.check.ms
availability.check.consecutive.failure.threshold
val AvailabilityCheckMsDefault = 60 * 1000
val AvailabilityCheckConsecutiveFailureThresholdDefault = 5


AVAILABILITY_CHECK_CONSECUTIVE_FAILURE_THRESHOLD

info(s"Cluster link $linkName is not available, moving to degraded state")
[2023-04-20 12:35:32,947] INFO [ClusterLinkManager-broker-1] Cluster link link-us-to-europe is not available, moving to degraded state (kafka.server.link.ClusterLinkManager)

Throughput don't get update when cluster link unavialable
Mirroring Throughput