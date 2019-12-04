CREATE STREAM ratings (id INT, rating DOUBLE)
    WITH (kafka_topic='ratings',
          partitions=2,
          value_format='avro');

CREATE STREAM RATINGS_REKEYED
  WITH (KAFKA_TOPIC='ratings_keyed_by_id') AS
    SELECT *
    FROM RATINGS
    PARTITION BY ID;