package io.confluent.developer.helper;


import akka.actor.ActorSystem;
import akka.kafka.ConsumerSettings;
import akka.kafka.Subscriptions;
import akka.kafka.javadsl.Consumer;
import akka.stream.ActorMaterializer;
import akka.stream.Materializer;
import akka.stream.scaladsl.Sink;
import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.kstream.Windowed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import scala.runtime.BoxedUnit;

import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.UUID;

import static org.apache.kafka.streams.kstream.WindowedSerdes.timeWindowedSerdeFrom;

public class ResultConsumer {

    private static final Logger logger = LoggerFactory.getLogger(ResultConsumer.class);

    public static void main(String[] args) {

        final Config config = ConfigFactory.load();
        final String outputTopic = config.getString("output.topic.name");

        final ActorSystem system = ActorSystem.create();
        final Materializer materializer = ActorMaterializer.create(system);

        final ConsumerSettings<Windowed<String>, Long> consumerSettings =
                ConsumerSettings
                        .create(
                                system,
                                timeWindowedSerdeFrom(
                                        String.class,
                                        config.getDuration("window.size").toMillis()
                                ).deserializer(),
                                Serdes.Long().deserializer()
                        )
                        .withGroupId(UUID.randomUUID().toString())
                        .withBootstrapServers(config.getString("bootstrap.servers"))
                        .withProperty(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");

        Consumer.plainSource(
                consumerSettings,
                Subscriptions.topics(outputTopic))
                .to(Sink.foreach((record) -> {
                            logger.info(printWindowedKey(config, record));
                            return BoxedUnit.UNIT;
                        })
                ).run(materializer);

    }

    private static String printWindowedKey(Config config, ConsumerRecord<Windowed<String>, Long> windowedKeyValue) {

        return String.format("Count = %s for Key = %s, at window [%s-%s] %s (%s)",
                windowedKeyValue.value().toString(),
                windowedKeyValue.key().key(),
                DateTimeFormatter
                        .ofPattern("HH:mm:ss")
                        .withLocale(Locale.getDefault())
                        .withZone(ZoneId.systemDefault())
                        .format(windowedKeyValue.key().window().startTime()),
                DateTimeFormatter
                        .ofPattern("HH:mm:ss")
                        .withLocale(Locale.getDefault())
                        .withZone(ZoneId.systemDefault())
                        .format(windowedKeyValue.key().window().endTime()),
                DateTimeFormatter
                        .ofPattern(config.getString("local.date.pattern"))
                        .withLocale(Locale.forLanguageTag(config.getString("local.date.lang")))
                        .withZone(ZoneId.systemDefault())
                        .format(windowedKeyValue.key().window().startTime()),
                ZoneId.systemDefault().getId()
        );
    }
}