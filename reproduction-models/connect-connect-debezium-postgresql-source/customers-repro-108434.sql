-- https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html
CREATE TABLE outboxevent (
  id UUID NOT NULL,
  aggregatetype VARCHAR(255) NULL,
  aggregateid VARCHAR(255) NULL,
  type VARCHAR(255) NOT NULL,
  payload JSONB NOT NULL,
  PRIMARY KEY (id)
);

INSERT INTO outboxevent (
  id,
  aggregatetype,
  aggregateid,
  type,
  payload
) VALUES (
  '406c07f3-26f0-4eea-a50c-109940064b8f',
  'Order',
  '1',
  'OrderCreated',
  '{ "phones":[ {"type": "mobile", "phone": "001001"} , {"type": "fix", "phone": "002002"} ] }'
);


