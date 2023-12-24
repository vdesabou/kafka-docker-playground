#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Create the table and insert data."
docker exec -i sybase /sybase/isql -S -Usa -Ppassword << EOF
CREATE DATABASE testDB
GO
USE testDB

CREATE TABLE customers(id INTEGER IDENTITY,first_name VARCHAR(255) NOT NULL,last_name VARCHAR(255) NOT NULL,email VARCHAR(255) NOT NULL,primary key( id ))
GO
INSERT INTO customers(first_name,last_name,email) VALUES ('Sally','Thomas','sally.thomas@acme.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('George','Bailey','gbailey@foobar.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('Edward','Walker','ed@walker.com')
INSERT INTO customers(first_name,last_name,email) VALUES ('Anne','Kretchmar','annek@noanswer.org')
GO
EOF

log "Creating JDBC Sybase source connector"
playground connector create-or-update --connector jdbc-sybase-source  << EOF
{
      "connector.class" : "io.confluent.connect.jdbc.JdbcSourceConnector",
      "tasks.max" : "1",
      "connection.url": "jdbc:jtds:sybase://sybase:5000/testDB",
      "connection.user": "sa",
      "connection.password": "password",
      "table.whitelist": "customers",
      "mode": "incrementing",
      "incrementing.column.name": "id",
      "topic.prefix": "sybase-",
      "validate.non.null":"false",
      "errors.log.enable": "true",
      "errors.log.include.messages": "true"
}
EOF

sleep 5

log "insert another record"
docker exec -i sybase /sybase/isql -S -Usa -Ppassword << EOF
USE testDB
GO
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com')
GO
EOF

log "Verifying topic sybase-customers"
playground topic consume --topic sybase-customers --min-expected-messages 5 --timeout 60