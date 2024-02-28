# Why tombstone is not propagated to table derived from CTAS in ksqlDB

## Objective

### Description

This Article will provide details on why a tombstone is not propagated to table derived from CTAS in ksqlDB

### Example

You have a stream like the following:
```
CREATE STREAM mystream
( product_key STRING KEY,
  date_created STRING,
  description STRING
) WITH
( KAFKA_TOPIC  = 'my_topic', KEY_FORMAT   = 'JSON', VALUE_FORMAT = 'JSON');
```

And you created a table based on the stream

```
CREATE TABLE mytable
with(KAFKA_TOPIC ='my_table_topic', PARTITIONS=8, KEY_FORMAT='JSON', VALUE_FORMAT='JSON')
AS
SELECT product_key
     , min(date_created)  as min_date_created
     , max(date_created)  as max_date_created
     , count(product_key)  as cnt
  FROM mystream
 GROUP BY product_key
EMIT CHANGES
;
```

When you put messages on topic mystream, as expected you see new (or updated) rows in the table mytable.
But when you put messages on topic my_topic with null values (ie: tombstones), you expect rows with message keys to be deleted but they still exist in a table.

This is the **expected** behaviour.

A STREAM ignores tombstone (A message with a NULL value is ignored.). As your table mytable is based on the STREAM mystream, when you produce a tombstone to the topic my_topic, it will be ignored by the STREAM mystream, so it will not be propagated to your table mytable.

See an example here: https://forum.confluent.io/t/tombstone-messages-not-propagated/2612

### Resolution

In your case, there are two workarounds to handle tombstone with a TABLE based on a STREAM (please find below an example for each workaround):

If you want to apply tombstone to mytable, then you will need to add a having clause
Use a source table based on your topic my_table_topic 

 
**Example with the HAVING clause:**
```
CREATE STREAM TEMP_CITY_FOO(CITY VARCHAR, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.foo',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

INSERT INTO TEMP_CITY_FOO VALUES('PUN','34');
INSERT INTO TEMP_CITY_FOO VALUES('MUM','38');
INSERT INTO TEMP_CITY_FOO VALUES('KOL','39');
INSERT INTO TEMP_CITY_FOO VALUES('MUM','41');
INSERT INTO TEMP_CITY_FOO VALUES('PUN','28');

CREATE TABLE TEMP_CITY_FOO_LATEST  WITH(KAFKA_TOPIC = 'temp.city.latest.foo',VALUE_FORMAT = 'AVRO', PARTITIONS = 1)
AS SELECT CITY,LATEST_BY_OFFSET(TEMP) AS TEMP FROM TEMP_CITY_FOO GROUP BY CITY HAVING latest_by_offset(TEMP, false) IS NOT NULL EMIT CHANGES;

ksql> SELECT * FROM TEMP_CITY_FOO_LATEST WHERE CITY = 'KOL';
>
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
|CITY                                                                                                        |TEMP                                                                                                        |
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
|KOL                                                                                                         |39                                                                                                          |

#You can add a "logical" tombstone to your topic
INSERT INTO TEMP_CITY_FOO VALUES('KOL',null);
#Because of the HAVING latest_by_offset(TEMP, false) IS NOT NULL clause, it will remove the value for the key `KOL`

ksql> SELECT * FROM TEMP_CITY_FOO_LATEST   WHERE CITY = 'KOL';
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
|CITY                                                                                                        |TEMP                                                                                                        |
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
Query terminated

ksql> print `temp.city.latest.foo` from beginning;
Key format: KAFKA_STRING
Value format: AVRO or KAFKA_STRING
rowtime: 2023/04/04 14:06:12.915 Z, key: KOL, value: {"TEMP": "39"}, partition: 0
rowtime: 2023/04/04 14:06:12.940 Z, key: MUM, value: {"TEMP": "41"}, partition: 0
rowtime: 2023/04/04 14:06:12.966 Z, key: PUN, value: {"TEMP": "28"}, partition: 0
rowtime: 2023/04/04 14:08:39.769 Z, key: KOL, value: <null>, partition: 0
```
 
As you can see, with this workaround, you are using the clause `HAVING latest_by_offset(TEMP, false) IS NOT NULL` to be able to remove the key from the aggregation if the value is null. This is not a true tombstone (so not a KAFKA NULL value), so it will not be ignored by the stream TEMP_CITY_FOO and it will be propagated to the table TEMP_CITY_FOO_LATEST and the table will delete the value from his state store and produce a true tombstone to the output topic. 
 
**Example with the source table:**

```
CREATE STREAM TEMP_CITY_BAR(CITY VARCHAR, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

INSERT INTO TEMP_CITY_BAR VALUES('PUN','34');
INSERT INTO TEMP_CITY_BAR VALUES('MUM','38');
INSERT INTO TEMP_CITY_BAR VALUES('KOL','39');
INSERT INTO TEMP_CITY_BAR VALUES('MUM','41');
INSERT INTO TEMP_CITY_BAR VALUES('PUN','28');

CREATE TABLE TEMP_CITY_BAR_LATEST  WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'AVRO', PARTITIONS = 1)
AS SELECT CITY,LATEST_BY_OFFSET(TEMP) AS TEMP FROM TEMP_CITY_BAR GROUP BY CITY EMIT CHANGES;

INSERT INTO TEMP_CITY_BAR VALUES('KOL','42');

CREATE STREAM TEMP_CITY_BAR_TOMBSTONE(CITY VARCHAR KEY, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'KAFKA');

INSERT INTO TEMP_CITY_BAR_TOMBSTONE VALUES('KOL',CAST(NULL AS VARCHAR));

CREATE SOURCE TABLE TEMP_CITY_BAR_LATEST_SOURCE(CITY VARCHAR PRIMARY KEY, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

ksql> SELECT * from TEMP_CITY_BAR_LATEST_SOURCE  WHERE CITY = 'KOL';
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
|CITY                                                                                                        |TEMP                                                                                                        |
+------------------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
Query terminated
ksql>
```

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

## Resources
https://forum.confluent.io/t/tombstone-messages-not-propagated/2612
