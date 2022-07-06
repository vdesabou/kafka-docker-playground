package com.github.vdesabou.kafka.connect.transforms;

import com.jayway.jsonpath.InvalidPathException;
import com.jayway.jsonpath.PathNotFoundException;
import org.apache.kafka.common.config.ConfigException;
import com.jayway.jsonpath.JsonPath;

import org.apache.kafka.connect.transforms.util.SimpleConfig;
import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.errors.DataException;
import org.apache.kafka.connect.transforms.Transformation;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;
import org.apache.kafka.connect.data.Field;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.Struct;
import org.apache.kafka.connect.errors.DataException;

import java.util.List;
import java.util.ArrayList;
import java.util.HashMap;

public class JsonFieldToKey<R extends ConnectRecord<R>> implements Transformation<R> {

  public static final String FIELD_CONFIG = "field";

  private static final Logger log = LoggerFactory.getLogger(JsonFieldToKey.class);

  public static final ConfigDef CONFIG_DEF = new ConfigDef()
      .define(
              FIELD_CONFIG,
              ConfigDef.Type.STRING,
              "",
              ConfigDef.Importance.HIGH,
              "Field to use as key (in jsonpath format, please refer to com.jayway.jsonpath java doc for correct use of jsonpath). Mandatory field."
      );

  private static final String KEY_USE_PURPOSE = "use as key";
  private static final String FIELD_EXTRACTION_PURPOSE = "field extraction";

  private Function<R, Object> keyExtractor;
  private String fieldName;
  private String fieldPathFormat;

  @Override
  public void configure(Map<String, ?> props) {
    final SimpleConfig config = new SimpleConfig(CONFIG_DEF, props);
    fieldName = config.getString(FIELD_CONFIG);
    if (fieldName.isEmpty()) {
      throw new ConfigException("The field configuration provided cannot be empty");
    }
    keyExtractor = new FieldJsonPathExtractor(fieldName);
  }

  @Override
  public R apply(R record) {
    Object keyObject = null;
    if (record.value() != null) {
      keyObject = keyExtractor.apply(record);
    }

    if (keyObject == null) {
      throw new DataException("Key could not be found, please check your json path");
    }

    return record.newRecord(
        record.topic(),
        record.kafkaPartition(),
        null, // TODO: no key schema for string, assume key.converter=org.apache.kafka.connect.storage.StringConverter
        requireString(keyObject, KEY_USE_PURPOSE),
        record.valueSchema(),
        record.value(),
        record.timestamp()
    );
  }

  public static String requireString(Object value, String purpose) {
    if (!(value instanceof String)) {
      throw new DataException("Only String objects supported for [" + purpose + "]; found: "
          + nullSafeClassName(value)
      );
    }
    return (String) value;
  }

  private static String nullSafeClassName(Object x) {
    return x == null ? "null" : x.getClass().getName();
  }

  @Override
  public void close() {
  }

  @Override
  public ConfigDef config() {
    return CONFIG_DEF;
  }


  protected class FieldJsonPathExtractor implements Function<R, Object> {
    private final String fieldName;
    private final JsonPath field;

    public FieldJsonPathExtractor(String fieldName) {
      try {
        this.fieldName = Objects.requireNonNull(fieldName, "Field name cannot be null");
        this.field = JsonPath.compile(this.fieldName);
      } catch (InvalidPathException e) {
        throw new InvalidPathException("Json Path `" + fieldName + "`specified in `"
             + FIELD_CONFIG + "`config is incorrectly formatted. "
             + "Please refer to com.jayway.jsonpath java doc for correct use of jsonpath.");
      }
    }

    @Override
    public Object apply(R record) {
      // TODO: check we have byte[] as input
      String payload = new String((byte[])record.value());
      Object fieldValue;
      try {
        fieldValue = this.field.read(payload);
      } catch (PathNotFoundException e) {
        fieldValue = null;
      }

      return fieldValue;
    }
  }
}
