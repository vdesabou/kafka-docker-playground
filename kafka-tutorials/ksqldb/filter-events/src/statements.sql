CREATE STREAM all_publications (author VARCHAR, title VARCHAR)
    WITH (kafka_topic = 'publication_events',
          partitions = 1,
          key = 'author',
          value_format = 'avro');

CREATE STREAM george_martin
    WITH (kafka_topic = 'george_martin_books',
          partitions = 1) AS
    SELECT author, title
    FROM all_publications
    WHERE author = 'George R. R. Martin';