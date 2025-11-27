CREATE TABLE "notused"."notused" (
  "id" int PRIMARY KEY,
  "name" varchar COMMENT 'faker.internet.userName()',
  "merchant_id" int NOT NULL COMMENT 'faker.number.int()',
  "price" int COMMENT 'faker.number.int()',
  "status" int COMMENT 'faker.datatype.boolean()'
);