// Configuration shared by the producer and the consumer.

use std::collections::HashMap;
use std::env;

/// Adds SASL_SSL / PLAIN (Confluent Cloud API key and secret) when the
/// SASL_USERNAME and SASL_PASSWORD environment variables are set: the
/// credentials never appear on the command line. PLAIN is the only SASL
/// mechanism of the Rust client 1.0.
pub fn add_sasl_config(props: &mut HashMap<String, String>) {
    if let (Ok(username), Ok(password)) = (env::var("SASL_USERNAME"), env::var("SASL_PASSWORD")) {
        let escape = |s: &str| s.replace('\\', "\\\\").replace('"', "\\\"");
        props.insert("security.protocol".to_string(), "SASL_SSL".to_string());
        props.insert("sasl.mechanism".to_string(), "PLAIN".to_string());
        props.insert(
            "sasl.jaas.config".to_string(),
            format!(
                "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"{}\" password=\"{}\";",
                escape(&username),
                escape(&password)
            ),
        );
    }
}
