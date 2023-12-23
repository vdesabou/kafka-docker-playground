#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Create the ksqlDB table and the Stream"
log "We have a table to represent the movie reference data and a stream to represent the ratings of those movies"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE TABLE movies (ID INT PRIMARY KEY, title VARCHAR, release_year INT)
    WITH (kafka_topic='movies', partitions=1, value_format='avro');

CREATE STREAM ratings (MOVIE_ID INT KEY, rating DOUBLE)
    WITH (kafka_topic='ratings', partitions=1, value_format='avro');

EOF

log "Insert the records"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO movies (id, title, release_year) VALUES (294, 'Die Hard', 1998);
INSERT INTO movies (id, title, release_year) VALUES (354, 'Tree of Life', 2011);
INSERT INTO movies (id, title, release_year) VALUES (782, 'A Walk in the Clouds', 1995);
INSERT INTO movies (id, title, release_year) VALUES (128, 'The Big Lebowski', 1998);
INSERT INTO movies (id, title, release_year) VALUES (780, 'Super Mario Bros.', 1993);

INSERT INTO ratings (movie_id, rating) VALUES (294, 8.2);
INSERT INTO ratings (movie_id, rating) VALUES (294, 8.5);
INSERT INTO ratings (movie_id, rating) VALUES (354, 9.9);
INSERT INTO ratings (movie_id, rating) VALUES (354, 9.7);
INSERT INTO ratings (movie_id, rating) VALUES (782, 7.8);
INSERT INTO ratings (movie_id, rating) VALUES (782, 7.7);
INSERT INTO ratings (movie_id, rating) VALUES (128, 8.7);
INSERT INTO ratings (movie_id, rating) VALUES (128, 8.4);
INSERT INTO ratings (movie_id, rating) VALUES (780, 2.1);

EOF

log "The following query will do a left join between the ratings stream and the movies table on the movie id"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT ratings.movie_id AS ID, title, release_year, rating
   FROM ratings
   LEFT JOIN movies ON ratings.movie_id = movies.id
   EMIT CHANGES LIMIT 9;
EOF

# This should yield the following output:
#
# +--------------------+--------------------+--------------------+--------------------+
# |ID                  |TITLE               |RELEASE_YEAR        |RATING              |
# +--------------------+--------------------+--------------------+--------------------+
# |294                 |Die Hard            |1998                |8.2                 |
# |294                 |Die Hard            |1998                |8.5                 |
# |354                 |Tree of Life        |2011                |9.9                 |
# |354                 |Tree of Life        |2011                |9.7                 |
# |782                 |A Walk in the Clouds|1995                |7.8                 |
# |782                 |A Walk in the Clouds|1995                |7.7                 |
# |128                 |The Big Lebowski    |1998                |8.7                 |
# |128                 |The Big Lebowski    |1998                |8.4                 |
# |780                 |Super Mario Bros.   |1993                |2.1                 |
# Limit Reached

log "We create a new stream based on this stream-table join"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM rated_movies
    WITH (kafka_topic='rated_movies',
          value_format='avro') AS
    SELECT ratings.movie_id as id, title, rating
    FROM ratings
    LEFT JOIN movies ON ratings.movie_id = movies.id;
EOF

# Wait for the stream to be initialized
sleep 5
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM rated_movies;
EOF
