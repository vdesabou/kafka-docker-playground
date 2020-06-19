using System.Collections.Generic;
using Newtonsoft.Json;

namespace Monitoring
{
    public class Statistics
    {
        [JsonProperty(PropertyName="topics")]
        public Dictionary<string, TopicStatistic> Topics { get; set; }

        public Statistics()
        {
            Topics = new Dictionary<string, TopicStatistic>();
        }
    }

    public class TopicStatistic
    {
        [JsonProperty(PropertyName="partitions")]
        public Dictionary<string, PartitionStatistic> Partitions { get; set; }

        public TopicStatistic()
        {
            Partitions = new Dictionary<string, PartitionStatistic>();
        }
    }

    public class PartitionStatistic
    {
        //producer
        [JsonProperty(PropertyName="txmsgs")]
        public long MessagesProduced { get; set; }

        [JsonProperty(PropertyName="txbytes")]
        public long BytesProduced { get; set; }

        // consumer
        [JsonProperty(PropertyName="consumer_lag")]
        public long ConsumerLag { get; set; }

        [JsonProperty(PropertyName="fetchq_cnt")]
        public long FetchQueueCount { get; set; }

        [JsonProperty(PropertyName="fetchq_size")]
        public long FetchQueueSize { get; set; }

        [JsonProperty(PropertyName="rxmsgs")]
        public long MessagesConsumed { get; set; }

        [JsonProperty(PropertyName="rxbytes")]
        public long BytesConsumed { get; set; }
    }
}