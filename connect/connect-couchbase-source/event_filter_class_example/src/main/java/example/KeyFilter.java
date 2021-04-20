package example;

import com.couchbase.connect.kafka.filter.Filter;
import com.couchbase.connect.kafka.handler.source.DocumentEvent;

public class KeyFilter implements Filter {

  public boolean pass(DocumentEvent message) {
    // replace airline by the key you want
    return message.key() != null && message.key().startsWith("airline");
  }
}