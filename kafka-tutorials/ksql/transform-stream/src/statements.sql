CREATE STREAM raw_movies (id int, title varchar, genre varchar)
    WITH (kafka_topic='movies', partitions=1, key='id', value_format = 'avro');

CREATE STREAM movies WITH (kafka_topic = 'parsed_movies', partitions = 1) AS
    SELECT id,
           split(title, '::')[0] as title,
           CAST(split(title, '::')[1] AS INT) AS year,
           genre
    FROM raw_movies;
