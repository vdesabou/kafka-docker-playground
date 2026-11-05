package io.confluent.playground.streams;

import java.util.Map;
import java.util.Properties;

import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Joined;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.KTable;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.state.KeyValueStore;

/**
 * join: orders (key: order id, value: {"customer":"c1","product":"p1",...}) joined two ways.
 *
 * - stream-table join with the customers table: the orders are re-keyed by customer, so Kafka Streams repartitions
 *   them (repartition topic) to be co-partitioned with the customers topic. An order whose customer is unknown is
 *   dropped (inner join). Output: orders-enriched.
 * - foreign-key join of the orders table with the products table: no co-partitioning needed, Kafka Streams uses
 *   subscription topics (KTABLE-FK-JOIN-SUBSCRIPTION-...). An update of a product re-emits the orders of that product.
 *   Output: orders-with-product.
 *
 * Demo "copartition-demo" (app.copartition.demo=true): joins orders-by-customer (6 partitions, already keyed by
 * customer) with the customers table (3 partitions) directly, without repartition. The two topics are not
 * co-partitioned. Up to Kafka Streams 3.1 the topology is refused (TopologyException: Topics not co-partitioned). Since
 * 3.2 co-partitioning is only validated when there are repartition topics ("Skipping the repartition topic validation
 * since there are no repartition topics", apache/kafka 529dde904a, KAFKA-12648): 6 tasks, tasks 3 to 5 get no partition
 * of the table, and an order joins only when its key lands in the same partition number in both topics. The other
 * orders are silently lost.
 */
class JoinScenario implements Scenario {

    private final boolean copartitionDemo;

    JoinScenario(Properties appProps) {
        this.copartitionDemo = Boolean.parseBoolean(appProps.getProperty("copartition.demo", "true"));
    }

    @Override
    public Map<String, Integer> topics() {
        return Map.of("customers", 3, "products", 2, "orders", 6, "orders-by-customer", 6);
    }

    @Override
    public Topology topology(Properties streamsProps) {
        StreamsBuilder builder = new StreamsBuilder();
        KTable<String, String> customers = builder.table("customers", Consumed.with(Serdes.String(), Serdes.String()),
                Materialized.<String, String, KeyValueStore<Bytes, byte[]>>as("customers-store"));
        KTable<String, String> products = builder.table("products", Consumed.with(Serdes.String(), Serdes.String()),
                Materialized.<String, String, KeyValueStore<Bytes, byte[]>>as("products-store"));
        KStream<String, String> orders = builder.stream("orders", Consumed.with(Serdes.String(), Serdes.String()));

        // stream-table join: re-keyed by customer, then repartitioned to be co-partitioned with customers
        orders.map((orderId, order) -> KeyValue.pair(Json.field(order, "customer"), "{\"order_id\":\"" + orderId + "\",\"order\":" + order + "}"))
                .join(customers, (order, customer) -> order.substring(0, order.length() - 1) + ",\"customer\":" + customer + "}",
                        Joined.with(Serdes.String(), Serdes.String(), Serdes.String(), "orders-customers-join"))
                .to("orders-enriched", Produced.with(Serdes.String(), Serdes.String()));

        // foreign-key join: the orders table, by the product of each order
        orders.toTable(Materialized.<String, String, KeyValueStore<Bytes, byte[]>>as("orders-store").withKeySerde(Serdes.String()).withValueSerde(Serdes.String()))
                .join(products, order -> Json.field(order, "product"), (order, product) -> "{\"order\":" + order + ",\"product\":" + product + "}")
                .toStream()
                .to("orders-with-product", Produced.with(Serdes.String(), Serdes.String()));
        return builder.build();
    }

    @Override
    public Map<String, Demo> demos() {
        if (!copartitionDemo) {
            return Map.of();
        }
        StreamsBuilder builder = new StreamsBuilder();
        KTable<String, String> customers = builder.table("customers", Consumed.with(Serdes.String(), Serdes.String()));
        builder.stream("orders-by-customer", Consumed.with(Serdes.String(), Serdes.String()))
                .join(customers, (order, customer) -> order + customer)
                .to("orders-by-customer-enriched", Produced.with(Serdes.String(), Serdes.String()));
        return Map.of("copartition-demo", new Demo(builder.build(), new Properties()));
    }
}
