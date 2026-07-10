import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class LccCollisionCheck {
    private static final int MAX_NUMERIC_CLUSTER_ID = 10240;

    private static String computeNumericClusterId(String logicalClusterId) {
        return Integer.toString(
            Math.abs(logicalClusterId.hashCode() % MAX_NUMERIC_CLUSTER_ID)
        );
    }

    private static List<String> loadLccList(String[] args) throws IOException {
        List<String> values = new ArrayList<>();

        if (args.length >= 2 && "--file".equals(args[0])) {
            for (String line : Files.readAllLines(Path.of(args[1]), StandardCharsets.UTF_8)) {
                String trimmed = line.trim();
                if (!trimmed.isEmpty()) {
                    values.add(trimmed);
                }
            }
            return values;
        }

        if (args.length > 0) {
            for (String arg : args) {
                String trimmed = arg.trim();
                if (!trimmed.isEmpty()) {
                    values.add(trimmed);
                }
            }
            return values;
        }

        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = reader.readLine()) != null) {
            String trimmed = line.trim();
            if (!trimmed.isEmpty()) {
                values.add(trimmed);
            }
        }

        return values;
    }

    public static void main(String[] args) throws Exception {
        List<String> lccs = loadLccList(args);

        if (lccs.isEmpty()) {
            System.err.println("No LCC values provided.");
            System.err.println("Usage:");
            System.err.println("  java LccCollisionCheck lcc1 lcc2 lcc3");
            System.err.println("  java LccCollisionCheck --file lcc-list.txt");
            System.err.println("  cat lcc-list.txt | java LccCollisionCheck");
            System.exit(1);
        }

        Map<String, Set<String>> numericToLogical = new LinkedHashMap<>();

        for (String lcc : lccs) {
            String numericClusterId = computeNumericClusterId(lcc);
            numericToLogical.computeIfAbsent(numericClusterId, k -> new LinkedHashSet<>()).add(lcc);
            System.out.printf("LCC=%s -> numericClusterId=%s%n", lcc, numericClusterId);
        }

        int collisionBuckets = 0;
        int totalCollidingValues = 0;

        System.out.println();
        System.out.println("Collision report:");

        for (Map.Entry<String, Set<String>> entry : numericToLogical.entrySet()) {
            if (entry.getValue().size() > 1) {
                collisionBuckets++;
                totalCollidingValues += entry.getValue().size();
                System.out.printf("COLLISION numericClusterId=%s lccs=%s%n", entry.getKey(), entry.getValue());
            }
        }

        if (collisionBuckets == 0) {
            System.out.println("No collisions found.");
            System.exit(0);
        } else {
            System.out.printf("Found %d collision bucket(s), %d colliding LCC value(s).%n",
                collisionBuckets, totalCollidingValues);
            System.exit(2);
        }
    }
}
