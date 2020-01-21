package com.github.vdesabou.kafka.connect.transforms;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Field;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaBuilder;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.transforms.Transformation;
import org.apache.kafka.connect.transforms.util.SchemaUtil;
import org.apache.kafka.connect.transforms.util.SimpleConfig;

import static org.apache.kafka.connect.transforms.util.Requirements.requireStruct;

import java.util.Map;

public class TombstoneToNull<R extends ConnectRecord<R>> implements Transformation<R> {

    public static final String OVERVIEW_DOC =
            "If this is a tombstone, set record's values to specific values";

    private static final ConfigDef CONFIG_DEF = new ConfigDef();

    @Override
    public void configure(Map<String, ?> props) {
        // do nothing
    }

    @Override
    public R apply(R record) {

        if (record.value() != null) {
            return record;
        }

        Schema dvSchema = SchemaBuilder.struct()
        .name("com.github.vdesabou.Customer").version(1).doc("Some doc.")
        .field("ListID", Schema.INT64_SCHEMA)
        .field("NormalizedHashItemID", Schema.INT64_SCHEMA)
        .field("URL", Schema.STRING_SCHEMA)
        .build();

        final Struct updatedValue = new Struct(dvSchema);
        updatedValue.put("ListID", 0L);
        updatedValue.put("NormalizedHashItemID", 0L);
        updatedValue.put("URL", "null");

        return record.newRecord(
                record.topic(),
                record.kafkaPartition(),
                record.keySchema(),
                record.key(),
                dvSchema,
                updatedValue,
                record.timestamp()
        );
    }

    @Override
    public void close() {
    }

    @Override
    public ConfigDef config() {
        return CONFIG_DEF;
    }

}