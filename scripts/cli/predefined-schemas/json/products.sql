CREATE TABLE "notused"."notused" (
    "id" int PRIMARY KEY COMMENT 'faker.number.int({ min: 1, max: 1000000 })',
    "name" varchar COMMENT 'faker.internet.userName()',
    "merchant_id" int NOT NULL COMMENT 'faker.number.int()',
    "price" int COMMENT 'faker.number.int()',
    "status" int COMMENT 'faker.datatype.boolean()',
    "created_at" datetime COMMENT 'faker.date.past().toISOString()'
);