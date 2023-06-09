CREATE TABLE "notused"."notused" (
  "id" int PRIMARY KEY,
  "name" varchar COMMENT 'faker.internet.userName()',
  "merchant_id" int NOT NULL COMMENT 'faker.datatype.number()',
  "price" int COMMENT 'faker.datatype.number()',
  "status" int COMMENT 'faker.datatype.boolean()'
);