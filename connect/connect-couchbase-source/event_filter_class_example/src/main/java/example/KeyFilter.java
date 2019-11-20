package example;

import com.couchbase.client.dcp.message.DcpMutationMessage;
import com.couchbase.client.deps.io.netty.buffer.ByteBuf;
import com.couchbase.connect.kafka.filter.Filter;

public class KeyFilter implements Filter {

  public boolean pass(ByteBuf message) {
    // replace airline by the key you want
    return DcpMutationMessage.is(message) && DcpMutationMessage.keyString(message).startsWith("airline");
  }
}