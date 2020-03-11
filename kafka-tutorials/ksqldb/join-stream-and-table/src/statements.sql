CREATE TABLE movies (ROWKEY INT KEY, title VARCHAR, release_year INT)
    WITH (kafka_topic='movies', partitions=1, value_format='avro');

CREATE STREAM ratings (ROWKEY INT KEY, rating DOUBLE)
    WITH (kafka_topic='ratings', partitions=1, value_format='avro');

CREATE STREAM rated_movies
    WITH (kafka_topic='rated_movies',
          partitions=1,
          value_format='avro') AS
    SELECT ratings.rowkey AS id, title, release_year, rating
    FROM ratings
    LEFT JOIN movies ON ratings.rowkey = movies.rowkey;