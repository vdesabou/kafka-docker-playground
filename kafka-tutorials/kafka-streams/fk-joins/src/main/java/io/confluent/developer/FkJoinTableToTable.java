package io.confluent.developer;


import io.confluent.common.utils.TestUtils;
import io.confluent.developer.avro.Album;
import io.confluent.developer.avro.MusicInterest;
import io.confluent.developer.avro.TrackPurchase;
import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;
import org.apache.avro.specific.SpecificRecord;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KTable;
import org.apache.kafka.streams.kstream.Produced;

import java.io.FileInputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CountDownLatch;

public class FkJoinTableToTable {


	public Properties buildStreamsProperties(Properties envProps) {
        Properties props = new Properties();

        props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
        props.put(StreamsConfig.STATE_DIR_CONFIG, TestUtils.tempDirectory().getPath());
        props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));

        return props;
    }

    public Topology buildTopology(Properties envProps) {
        final StreamsBuilder builder = new StreamsBuilder();
        final String albumTopic = envProps.getProperty("album.topic.name");
        final String userTrackPurchaseTopic = envProps.getProperty("tracks.purchase.topic.name");
        final String musicInterestTopic = envProps.getProperty("music.interest.topic.name");

        final Serde<Long> longSerde = getPrimitiveAvroSerde(envProps, true);
        final Serde<MusicInterest> musicInterestSerde = getSpecificAvroSerde(envProps);
        final Serde<Album> albumSerde = getSpecificAvroSerde(envProps);
        final Serde<TrackPurchase> trackPurchaseSerde = getSpecificAvroSerde(envProps);

        final KTable<Long, Album> albums = builder.table(albumTopic, Consumed.with(longSerde, albumSerde));

        final KTable<Long, TrackPurchase> trackPurchases = builder.table(userTrackPurchaseTopic, Consumed.with(longSerde, trackPurchaseSerde));
        final MusicInterestJoiner trackJoiner = new MusicInterestJoiner();

        final KTable<Long, MusicInterest> musicInterestTable = trackPurchases.join(albums,
                                                                             TrackPurchase::getAlbumId,
                                                                             trackJoiner);

        musicInterestTable.toStream().to(musicInterestTopic, Produced.with(longSerde, musicInterestSerde));

        return builder.build();
    }

    @SuppressWarnings("unchecked")
    static <T> Serde<T> getPrimitiveAvroSerde(final Properties envProps, boolean isKey) {
        final KafkaAvroDeserializer deserializer = new KafkaAvroDeserializer();
        final KafkaAvroSerializer serializer = new KafkaAvroSerializer();
        final Map<String, String> config = new HashMap<>();
        config.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG,
                envProps.getProperty("schema.registry.url"));
        deserializer.configure(config, isKey);
        serializer.configure(config, isKey);
        return (Serde<T>)Serdes.serdeFrom(serializer, deserializer);
    }

    static <T extends SpecificRecord> SpecificAvroSerde<T> getSpecificAvroSerde(final Properties envProps) {
        final SpecificAvroSerde<T> specificAvroSerde = new SpecificAvroSerde<>();

        final HashMap<String, String> serdeConfig = new HashMap<>();
        serdeConfig.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG,
                envProps.getProperty("schema.registry.url"));

        specificAvroSerde.configure(serdeConfig, false);
        return specificAvroSerde;
    }

    public void createTopics(final Properties envProps) {
        final Map<String, Object> config = new HashMap<>();
        config.put("bootstrap.servers", envProps.getProperty("bootstrap.servers"));
        final AdminClient client = AdminClient.create(config);

        final List<NewTopic> topics = new ArrayList<>();

        topics.add(new NewTopic(
                envProps.getProperty("album.topic.name"),
                Integer.parseInt(envProps.getProperty("album.topic.partitions")),
                Short.parseShort(envProps.getProperty("album.topic.replication.factor"))));

        topics.add(new NewTopic(
                envProps.getProperty("tracks.purchase.topic.name"),
                Integer.parseInt(envProps.getProperty("tracks.purchase.topic.partitions")),
                Short.parseShort(envProps.getProperty("tracks.purchase.topic.replication.factor"))));

        topics.add(new NewTopic(
                envProps.getProperty("music.interest.topic.name"),
                Integer.parseInt(envProps.getProperty("music.interest.topic.partitions")),
                Short.parseShort(envProps.getProperty("music.interest.topic.replication.factor"))));

        client.createTopics(topics);
        client.close();
    }

    public Properties loadEnvProperties(String fileName) throws IOException {
        final Properties envProps = new Properties();
        final FileInputStream input = new FileInputStream(fileName);
        envProps.load(input);
        input.close();

        return envProps;
    }

    public static void main(String[] args) throws Exception {

        if (args.length < 1) {
            throw new IllegalArgumentException("This program takes one argument: the path to an environment configuration file.");
        }

        final FkJoinTableToTable tableFkJoin = new FkJoinTableToTable();
        final Properties envProps = tableFkJoin.loadEnvProperties(args[0]);
        final Properties streamProps = tableFkJoin.buildStreamsProperties(envProps);
        final Topology topology = tableFkJoin.buildTopology(envProps);

        tableFkJoin.createTopics(envProps);

        final KafkaStreams streams = new KafkaStreams(topology, streamProps);
        final CountDownLatch latch = new CountDownLatch(1);

        // Attach shutdown handler to catch Control-C.
        Runtime.getRuntime().addShutdownHook(new Thread("streams-shutdown-hook") {
            @Override
            public void run() {
                streams.close(Duration.ofSeconds(5));
                latch.countDown();
            }
        });

        try {
            streams.start();
            latch.await();
        } catch (Throwable e) {
            System.exit(1);
        }
        System.exit(0);
    }

}