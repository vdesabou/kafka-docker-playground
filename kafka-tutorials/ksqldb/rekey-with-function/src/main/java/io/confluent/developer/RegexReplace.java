package io.confluent.developer;

import io.confluent.ksql.function.udf.Udf;
import io.confluent.ksql.function.udf.UdfDescription;
import io.confluent.ksql.function.udf.UdfParameter;

@UdfDescription(name = "regexReplace", description = "Replace string using a regex")
public class RegexReplace {

  @Udf(description = "regexReplace string using a regex")
  public String regexReplace(
    @UdfParameter(value = "input", description = "If null, then function returns null.") final String input,
    @UdfParameter(value = "regex", description = "If null, then function returns null.") final String regex,
    @UdfParameter(value = "replacement", description = "If null, then function returns null.") final String replacement) {
      if (input == null || regex == null || replacement == null) {
        return null;
      }
      return input.replaceAll(regex, replacement);
  }
}