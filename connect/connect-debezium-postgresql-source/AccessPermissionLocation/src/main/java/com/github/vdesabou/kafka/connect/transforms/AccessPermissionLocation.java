package com.github.vdesabou.kafka.connect.transforms;

import org.apache.kafka.connect.data.SchemaBuilder;

import java.nio.ByteBuffer;
import java.util.Properties;
import java.util.UUID;

import io.debezium.spi.converter.CustomConverter;
import io.debezium.spi.converter.RelationalColumn;
import org.apache.commons.codec.binary.Base64;

public class AccessPermissionLocation implements CustomConverter < SchemaBuilder, RelationalColumn > {

    private SchemaBuilder accessPermissionLocationSchema;

    private static String uuidToBase64(String str) {
        Base64 base64 = new Base64();
        UUID uuid = UUID.fromString(str);
        ByteBuffer bb = ByteBuffer.wrap(new byte[16]);
        bb.putLong(uuid.getMostSignificantBits());
        bb.putLong(uuid.getLeastSignificantBits());
        return base64.encodeBase64URLSafeString(bb.array());
    }

    @Override
    public void configure(Properties props) {
        accessPermissionLocationSchema = SchemaBuilder.string().name(props.getProperty("schema.name"));
    }

    @Override
    public void converterFor(RelationalColumn column, ConverterRegistration < SchemaBuilder > registration) {
        System.out.printf(
            "[TimestampConverter.converterFor] Starting to register column. column.name: %s, column.typeName: %s%n",
            column.name(), column.typeName());
        if ("access_permission_id".equals(column.typeName())) {
            registration.register(accessPermissionLocationSchema, rawValue - > {
                if (rawValue == null)
                    return rawValue;

                System.out.printf(
                    "[TimestampConverter.converterFor] Before returning conversion. column.name: %s, column.typeName: %s",
                    column.name(), column.typeName());

                return rawValue.toString();

            });
        }
    }
}