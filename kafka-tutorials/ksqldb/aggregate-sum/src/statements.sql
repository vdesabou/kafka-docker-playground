CREATE STREAM MOVIE_TICKET_SALES (title VARCHAR, sale_ts VARCHAR, ticket_total_value INT)
    WITH (KAFKA_TOPIC='movie-ticket-sales',
          PARTITIONS=1,
          VALUE_FORMAT='avro',
          TIMESTAMP='sale_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX');

CREATE TABLE MOVIE_REVENUE AS
    SELECT TITLE,
           SUM(TICKET_TOTAL_VALUE) AS TOTAL_VALUE
    FROM MOVIE_TICKET_SALES
    GROUP BY TITLE;