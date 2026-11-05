// Consumes <topic> from the beginning with the Confluent Rust client, using the
// KIP-848 consumer group protocol (group.protocol=consumer, the only one the
// client supports), and commits the offsets after each batch.
// Exits 0 once <nb-messages> records are consumed, 1 after <timeout-seconds>.
// SASL_USERNAME / SASL_PASSWORD environment variables: SASL_SSL (Confluent Cloud).
//
// usage: consumer <bootstrap-servers> <topic> <group-id> <nb-messages> <timeout-seconds>

use std::collections::HashMap;
use std::env;
use std::time::{Duration, Instant};

mod common;

use confluent_kafka::common::serialization::StringDeserializer;
use confluent_kafka::consumer::{Consumer, ConsumerConfig, KafkaConsumer};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 6 {
        eprintln!(
            "usage: {} <bootstrap-servers> <topic> <group-id> <nb-messages> <timeout-seconds>",
            args[0]
        );
        std::process::exit(1);
    }
    let bootstrap_servers = &args[1];
    let topic = &args[2];
    let group_id = &args[3];
    let nb_messages: usize = args[4].parse()?;
    let timeout = Duration::from_secs(args[5].parse()?);

    let mut props = HashMap::from([
        ("bootstrap.servers".to_string(), bootstrap_servers.to_string()),
        ("group.id".to_string(), group_id.to_string()),
        ("group.protocol".to_string(), "consumer".to_string()),
        ("auto.offset.reset".to_string(), "earliest".to_string()),
        ("enable.auto.commit".to_string(), "false".to_string()),
        ("client.id".to_string(), "client-rust-consumer".to_string()),
    ]);
    common::add_sasl_config(&mut props);
    let config = ConsumerConfig::new(&props)?;
    let mut consumer = KafkaConsumer::<String, String>::new(
        config,
        StringDeserializer::new(),
        StringDeserializer::new(),
    )?;

    consumer.subscribe_with_topics(vec![topic.to_string()]).await?;

    let start = Instant::now();
    let mut nb_consumed = 0;
    while nb_consumed < nb_messages {
        if start.elapsed() > timeout {
            eprintln!("Timeout: consumed {nb_consumed} records out of {nb_messages} after {timeout:?}");
            std::process::exit(1);
        }
        let records = consumer.poll(Duration::from_millis(500)).await?;
        for record in &records {
            println!(
                "Consumed record from {} [{}] at offset {}: key={:?} value={:?}",
                record.topic(),
                record.partition(),
                record.offset(),
                record.key(),
                record.value()
            );
        }
        if !records.is_empty() {
            nb_consumed += records.count();
            consumer.commit_sync().await?;
        }
    }

    // leave the group now: without close(), the member stays in the group until its session times out
    consumer.close().await?;
    println!("{nb_consumed} records were consumed from topic {topic} by group {group_id}");
    Ok(())
}
