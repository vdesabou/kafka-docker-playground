// Produces <nb-messages> records (key "key-<i>", value {"count":<i>}) to <topic>
// with the Confluent Rust client, and waits for every acknowledgement.
//
// usage: producer <bootstrap-servers> <topic> <nb-messages>

use std::collections::HashMap;
use std::env;

use confluent_kafka::common::serialization::StringSerializer;
use confluent_kafka::producer::{KafkaProducer, Producer, ProducerConfig, ProducerRecord};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: {} <bootstrap-servers> <topic> <nb-messages>", args[0]);
        std::process::exit(1);
    }
    let bootstrap_servers = &args[1];
    let topic = &args[2];
    let nb_messages: u32 = args[3].parse()?;

    let props = HashMap::from([
        ("bootstrap.servers".to_string(), bootstrap_servers.to_string()),
        ("acks".to_string(), "all".to_string()),
        ("client.id".to_string(), "client-rust-producer".to_string()),
    ]);
    let config = ProducerConfig::new(&props)?;
    let producer = KafkaProducer::<String, String>::new(
        config,
        StringSerializer::new(),
        StringSerializer::new(),
    )?;

    let mut acks = Vec::new();
    for i in 0..nb_messages {
        let record = ProducerRecord::with_key(
            topic.to_string(),
            Some(format!("key-{i}")),
            Some(format!("{{\"count\":{i}}}")),
        );
        acks.push(producer.send(record).await?);
    }

    let mut nb_produced = 0;
    for ack in acks {
        let metadata = ack.get().await?;
        println!(
            "Produced record to {} [{}] at offset {}",
            metadata.topic(),
            metadata.partition(),
            metadata.offset()
        );
        nb_produced += 1;
    }

    producer.close().await?;
    println!("{nb_produced} records were produced to topic {topic}");
    Ok(())
}
