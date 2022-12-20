package com.github.vdesabou.kafka.connect.transforms;

import java.util.Map;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.transforms.Transformation;

public class MyCustomSMT<R extends ConnectRecord<R>> implements Transformation<R> {

    public static final String OVERVIEW_DOC = "";
    public static final ConfigDef CONFIG_DEF = new ConfigDef();

    @Override
    public R apply(R record) {
        return null;
    }

    @Override
    public ConfigDef config() {
        return CONFIG_DEF;
    }

    @Override
    public void close() {

    }

    @Override
    public void configure(Map<String, ?> configs) {

    }
}