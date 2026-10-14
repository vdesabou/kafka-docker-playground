import java.util.*;

// Heap dump sample for playground analyze heap-dump: a session cache that is never evicted.
public class SessionCacheLeak {
    static final class Session {
        final String id; final String user; final byte[] payload; final List<String> tags = new ArrayList<>();
        Session(long n) {
            id = "session-" + n; user = "user-" + (n % 500);
            payload = new byte[256]; Arrays.fill(payload, (byte) (n % 7));
            for (int i = 0; i < 4; i++) tags.add("tag-" + (n % 50) + "-" + i);
        }
    }
    // the leak: entries are added on every request and never removed
    static final Map<String, Session> CACHE = new HashMap<>();

    public static void main(String[] args) throws Exception {
        long n = 0;
        while (true) {
            for (int i = 0; i < 50; i++, n++) { Session s = new Session(n); CACHE.put(s.id, s); }
            Thread.sleep(50);
        }
    }
}
