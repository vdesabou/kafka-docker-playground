#!/usr/bin/env python3
"""Flink SQL CREATE TABLE for a Kafka topic, the columns taken from its Avro value schema: 'playground flink table-ddl'.

  flink_ddl.py --table <name> --topic <topic> [--sink] [--bootstrap broker:9092] [--schema-registry http://schema-registry:8081] < schema.json

stdin: the Avro schema (the 'schema' string of GET /subjects/<subject>/versions/latest, or the schema itself). Every
column is nullable: Avro schema resolution reads a non-null writer field into a nullable reader one. The key of the
records is not read (value only).
"""

import argparse
import json
import sys

PRIMITIVES = {
    "null": "NULL", "boolean": "BOOLEAN", "int": "INT", "long": "BIGINT", "float": "FLOAT", "double": "DOUBLE",
    "bytes": "BYTES", "string": "STRING",
}


class Unsupported(Exception):
    pass


def ident(name):
    return "`%s`" % name.replace("`", "``")


def flink_type(schema, named, stack=()):
    if isinstance(schema, list):
        branches = [b for b in schema if b != "null"]
        if len(branches) != 1:
            raise Unsupported("union of %s: Flink has no type for a union of several types" % json.dumps(schema))
        return flink_type(branches[0], named, stack)
    if isinstance(schema, str):
        if schema in PRIMITIVES:
            if schema == "null":
                raise Unsupported("a field of type null")
            return PRIMITIVES[schema]
        if schema in named:
            if schema in stack:
                raise Unsupported("recursive record %s" % schema)
            return flink_type(named[schema], named, stack)
        raise Unsupported("unknown type %s" % schema)
    t = schema.get("type")
    logical = schema.get("logicalType")
    if logical == "decimal":
        return "DECIMAL(%d, %d)" % (schema.get("precision", 38), schema.get("scale", 0))
    if logical == "date":
        return "DATE"
    if logical == "time-millis":
        return "TIME(3)"
    if logical in ("timestamp-millis", "local-timestamp-millis"):
        return "TIMESTAMP(3)"
    if logical in ("timestamp-micros", "local-timestamp-micros"):
        return "TIMESTAMP(6)"
    if t == "record":
        name = schema.get("name", "")
        full = (schema.get("namespace", "") + "." + name).lstrip(".")
        named[name] = schema
        named[full] = schema
        if name in stack:
            raise Unsupported("recursive record %s" % name)
        fields = ", ".join("%s %s" % (ident(f["name"]), flink_type(f["type"], named, stack + (name,))) for f in schema["fields"])
        return "ROW<%s>" % fields
    if t == "enum":
        named[schema.get("name", "")] = schema
        return "STRING"
    if t == "fixed":
        named[schema.get("name", "")] = schema
        return "BYTES"
    if t == "array":
        return "ARRAY<%s>" % flink_type(schema["items"], named, stack)
    if t == "map":
        return "MAP<STRING, %s>" % flink_type(schema["values"], named, stack)
    if isinstance(t, (str, list, dict)):
        return flink_type(t, named, stack)
    raise Unsupported("type %s" % json.dumps(schema))


def columns(schema, field=None):
    if isinstance(schema, str):
        schema = json.loads(schema)
    if isinstance(schema, dict) and "schema" in schema and isinstance(schema["schema"], str):
        if schema.get("schemaType", "AVRO") != "AVRO":
            raise Unsupported("a %s schema: the Flink step reads Avro values only (format avro-confluent)" % schema["schemaType"])
        schema = json.loads(schema["schema"])
    if not isinstance(schema, dict) or schema.get("type") != "record":
        raise Unsupported("the value schema is not an Avro record")
    named = {}
    flink_type(schema, named)  # registers the named types
    if field:
        # the columns of a record field (the 'after' of a Debezium envelope)
        found = [f for f in schema["fields"] if f["name"] == field]
        if not found:
            raise Unsupported("no field %s in the value schema" % field)
        record = found[0]["type"]
        if isinstance(record, list):
            record = [b for b in record if b != "null"][0] if len([b for b in record if b != "null"]) == 1 else record
        if isinstance(record, str):
            record = named.get(record, record)
        if not isinstance(record, dict) or record.get("type") != "record":
            raise Unsupported("field %s is not a record" % field)
        return [(f["name"], flink_type(f["type"], named)) for f in record["fields"]]
    return [(f["name"], flink_type(f["type"], named)) for f in schema["fields"]]


def select(field, cols, source_table):
    """SELECT of the columns of a record field, the rows where it is not null (a delete of Debezium has no 'after')."""
    return "SELECT %s FROM %s WHERE %s IS NOT NULL" % (
        ", ".join("%s.%s AS %s" % (ident(field), ident(n), ident(n)) for n, _ in cols), ident(source_table), ident(field))


def ddl(table, topic, cols, sink=False, bootstrap="broker:9092", schema_registry="http://schema-registry:8081"):
    lines = ["CREATE TABLE %s (" % ident(table)]
    lines.append(",\n".join("  %s %s" % (ident(n), t) for n, t in cols))
    lines.append(") WITH (")
    opts = [("connector", "kafka"), ("topic", topic), ("properties.bootstrap.servers", bootstrap)]
    if not sink:
        opts += [("properties.group.id", "flink-" + table), ("scan.startup.mode", "earliest-offset")]
    opts += [("value.format", "avro-confluent"), ("value.avro-confluent.url", schema_registry)]
    lines.append(",\n".join("  '%s' = '%s'" % (k, v.replace("'", "''")) for k, v in opts))
    lines.append(");")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--table", default="t")
    p.add_argument("--topic", required=True)
    p.add_argument("--sink", action="store_true", help="a table written by an INSERT INTO: no consumer group nor startup mode")
    p.add_argument("--field", help="the columns of this record field of the value (the 'after' of a Debezium envelope)")
    p.add_argument("--select-from", help="print the SELECT of the columns of --field from this table instead of the CREATE TABLE")
    p.add_argument("--bootstrap", default="broker:9092")
    p.add_argument("--schema-registry", default="http://schema-registry:8081")
    a = p.parse_args()
    if a.select_from and not a.field:
        p.error("--select-from needs --field")
    try:
        cols = columns(sys.stdin.read(), a.field)
    except (Unsupported, ValueError, KeyError) as e:
        print("❌ %s" % e, file=sys.stderr)
        sys.exit(1)
    if a.select_from:
        print(select(a.field, cols, a.select_from))
        return
    print(ddl(a.table, a.topic, cols, a.sink, a.bootstrap, a.schema_registry))


if __name__ == "__main__":
    main()
