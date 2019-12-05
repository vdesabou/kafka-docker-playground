package io.confluent.developer.serialization.serde;

import com.google.gson.Gson;

import org.apache.kafka.common.serialization.Deserializer;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.serialization.Serializer;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import io.confluent.developer.avro.Movie;

public class MovieJsonSerde extends Serdes.WrapperSerde<Movie> {

  public MovieJsonSerde() {
    super(new Serializer<Movie>() {
      private Gson gson = new Gson();

      @Override
      public void configure(Map<String, ?> map, boolean b) {
      }

      @Override
      public byte[] serialize(String topic, Movie data) {
        return gson.toJson(data).getBytes(StandardCharsets.UTF_8);
      }

      @Override
      public void close() {
      }
    }, new Deserializer<Movie>() {
      private Gson gson = new Gson();

      @Override
      public void configure(Map<String, ?> configs, boolean isKey) {

      }

      @Override
      public Movie deserialize(String topic, byte[] data) {

        return gson.fromJson(new String(data), Movie.class);
      }

      @Override
      public void close() {

      }
    });
  }
}