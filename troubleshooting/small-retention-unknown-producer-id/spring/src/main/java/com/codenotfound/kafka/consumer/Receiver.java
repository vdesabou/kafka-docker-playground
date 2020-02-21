package com.codenotfound.kafka.consumer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.core.KafkaTemplate;

public class Receiver {

  @Autowired
  private KafkaTemplate<String, String> kafkaTemplate;

  private static final Logger LOGGER =
      LoggerFactory.getLogger(Receiver.class);


  @KafkaListener(topics = "testtopic")
  public void receive(String payload) {
    LOGGER.info("received payload='{}'", payload);

    kafkaTemplate.send("outputtesttopic", 0, 1581583089003L, null, "fwd " + payload);
  }
}
