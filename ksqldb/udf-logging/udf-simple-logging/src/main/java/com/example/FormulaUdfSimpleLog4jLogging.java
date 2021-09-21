package com.example;

import io.confluent.ksql.function.udf.Udf;
import io.confluent.ksql.function.udf.UdfDescription;
import io.confluent.ksql.function.udf.UdfParameter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@UdfDescription(name = "formula_simple_log4j_logging",
        author = "example",
        version = "1.0.0",
        description = "A custom formula for important business logic.")
public class FormulaUdfSimpleLog4jLogging {

    public static final Logger log = LoggerFactory.getLogger(FormulaUdfSimpleLog4jLogging.class);

    @Udf(description = "The standard version of the formula with integer parameters.")
    public long formula(@UdfParameter(value = "v1") final int v1, @UdfParameter(value = "v") final int v2) {
        log.info("V1: {}, V2: {}", v1, v2);
        return (v1 * v2);
    }
}
