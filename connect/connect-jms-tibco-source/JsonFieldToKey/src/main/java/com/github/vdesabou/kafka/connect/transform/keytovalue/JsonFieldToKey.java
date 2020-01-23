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
import java.util.Map;
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
        null, // no key schema for string, assume key.converter=org.apache.kafka.connect.storage.StringConverter
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

  @SuppressWarnings("unchecked")
  public static Map<String, Object> requireMap(Object value, String purpose) {
    if (!(value instanceof Map)) {
      throw new DataException(
          "Only Map objects supported in absence of schema for [" + purpose + "], found: "
              + nullSafeClassName(value)
      );
    }
    return (Map<String, Object>) value;
  }

  public static Struct requireStruct(Object value, String purpose) {
    if (!(value instanceof Struct)) {
      throw new DataException("Only Struct objects supported for [" + purpose + "], found: "
          + nullSafeClassName(value)
      );
    }
    return (Struct) value;
  }

  private static String nullSafeClassName(Object x) {
    return x == null ? "null" : x.getClass().getName();
  }

  private static Map<String, Object> convertStruct(Struct kafkaConnectStruct,
                                                  Schema kafkaConnectSchema) {
    Map<String, Object> record = new HashMap<>();

    for (Field kafkaConnectField : kafkaConnectSchema.fields()) {
      Object value = convertObject(
              kafkaConnectStruct.get(kafkaConnectField.name()),
              kafkaConnectField.schema()
      );
      if (value != null) {
        record.put(kafkaConnectField.name(), value);
      }
    }
    return record;
  }

  @SuppressWarnings("unchecked")
  public static Object convertObject(Object kafkaConnectObject, Schema kafkaConnectSchema) {
    if (kafkaConnectObject == null) {
      if (kafkaConnectSchema.isOptional()) {
        // short circuit converting the object
        return null;
      } else {
        throw new DataException(
          kafkaConnectSchema.name() + " is not optional, but converting object had null value");
      }
    }
    if (kafkaConnectSchema.type().isPrimitive()) {
      return kafkaConnectObject;
    }

    Schema.Type kafkaConnectSchemaType = kafkaConnectSchema.type();
    switch (kafkaConnectSchemaType) {
      case ARRAY:
        return convertArray((List<Object>) kafkaConnectObject, kafkaConnectSchema);
      case MAP:
        return convertMap((Map<Object, Object>)kafkaConnectObject, kafkaConnectSchema);
      case STRUCT:
        return convertStruct((Struct) kafkaConnectObject, kafkaConnectSchema);
      default:
        throw new DataException("Unrecognized schema type: " + kafkaConnectSchemaType);
    }
  }

  @SuppressWarnings("unchecked")
  private static List<Object> convertArray(List<Object> kafkaConnectList,
                                           Schema kafkaConnectSchema) {
    Schema kafkaConnectValueSchema = kafkaConnectSchema.valueSchema();
    List<Object> list = new ArrayList<>();
    for (Object kafkaConnectElement : kafkaConnectList) {
      Object element = convertObject(kafkaConnectElement, kafkaConnectValueSchema);
      list.add(element);
    }
    return list;
  }

  @SuppressWarnings("unchecked")
  private static Object convertMap(Map<Object, Object> kafkaConnectMap,
                                                      Schema kafkaConnectSchema) {
    Schema kafkaConnectKeySchema = kafkaConnectSchema.keySchema();
    Schema kafkaConnectValueSchema = kafkaConnectSchema.valueSchema();

    List<Map<String, Object>> entryList = new ArrayList<>();
    Map<Object, Object> map = new HashMap<>();

    boolean isMap = kafkaConnectKeySchema.type() == Schema.Type.STRING;

    for (Map.Entry kafkaConnectMapEntry : kafkaConnectMap.entrySet()) {
      Map<String, Object> entry = new HashMap<>();
      Object key = convertObject(
              kafkaConnectMapEntry.getKey(),
              kafkaConnectKeySchema
      );
      Object value = convertObject(
              kafkaConnectMapEntry.getValue(),
              kafkaConnectValueSchema
      );

      if (isMap) {
        map.put(key, value);
      } else {
        entry.put("key", key);
        entry.put("value", value);
        entryList.add(entry);
      }
    }

    return isMap ? map : entryList;
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
      final Schema schema = record.valueSchema();
      Object data = schema == null
              ? requireMap(record.value(), FIELD_EXTRACTION_PURPOSE)
              : convertObject(
                  requireStruct(record.value(), FIELD_EXTRACTION_PURPOSE),
                  ((Struct) record.value()).schema()
              );

      Object fieldValue;
      try {
        // not use DEFAULT_PATH_LEAF_TO_NULL since it does not
        // deal with $.a.b.c where b is already missing
        fieldValue = this.field.read(data);
      } catch (PathNotFoundException e) {
        fieldValue = null;
      }

      return fieldValue;
    }
  }
}
