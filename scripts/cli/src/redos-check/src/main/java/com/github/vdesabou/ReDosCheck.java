package com.github.vdesabou;

import codes.quine.labs.recheck.ReDoS;
import codes.quine.labs.recheck.common.Parameters;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import scala.Option;

import java.util.concurrent.TimeUnit;

public class ReDosCheck {

    private final Logger logger = LoggerFactory.getLogger(ReDosCheck.class);
    private static final Logger log = LoggerFactory.getLogger(ReDosCheck.class);

    public static void main(String[] args) {
        ReDosCheck checker = new ReDosCheck();
        
        if (args.length < 1) {
            System.err.println("Usage: java -jar redos-check-1.0.0-jar-with-dependencies.jar <regex> [timeout_seconds]");
            System.exit(1);
        }
        
        String topicRegex = args[0];
        int timeoutSeconds = 1;
        
        if (args.length > 1 && StringUtils.isNotBlank(args[1])) {
            try {
                timeoutSeconds = Integer.parseInt(args[1]);
            } catch (NumberFormatException e) {
                log.error("Invalid value for timeout: {}", args[1], e);
            }
        }
        
        timeoutSeconds = Math.min(timeoutSeconds, 10); // limit to 10 seconds
        timeoutSeconds = Math.max(timeoutSeconds, 1); // ensure at least 1 second
        
        int result = checker.checkRegex(topicRegex, timeoutSeconds);
        System.exit(result);
    }
    
    private int checkRegex(String topicRegex, int timeoutSeconds) {
        if (StringUtils.isBlank(topicRegex)) {
            System.out.println("SAFE: The topic regex '" + topicRegex + "' is safe");
            return 0;
        }
        
        Parameters params = new Parameters(
            Parameters.DefaultAccelerationMode(),
            Parameters.DefaultAttackLimit(),
            Parameters.DefaultAttackTimeout(),
            Parameters.DefaultChecker(),
            Parameters.DefaultCrossoverSize(),
            Parameters.DefaultHeatRatio(),
            Parameters.DefaultIncubationLimit(),
            Parameters.DefaultIncubationTimeout(),
            Parameters.DefaultLogger(),
            Parameters.DefaultMaxAttackStringSize(),
            Parameters.DefaultMaxDegree(),
            Parameters.DefaultMaxGeneStringSize(),
            Parameters.DefaultMaxGenerationSize(),
            Parameters.DefaultMaxInitialGenerationSize(),
            Parameters.DefaultMaxIteration(),
            Parameters.DefaultMaxNFASize(),
            Parameters.DefaultMaxPatternSize(),
            Parameters.DefaultMaxRecallStringSize(),
            Parameters.DefaultMaxRepeatCount(),
            Parameters.DefaultMaxSimpleRepeatCount(),
            Parameters.DefaultMutationSize(),
            Parameters.DefaultRandomSeed(),
            Parameters.DefaultRecallLimit(),
            Parameters.DefaultRecallTimeout(),
            Parameters.DefaultSeeder(),
            Parameters.DefaultSeedingLimit(),
            Parameters.DefaultSeedingTimeout(),
            scala.concurrent.duration.Duration.create(timeoutSeconds, TimeUnit.SECONDS)
        );
        
        try {
            Object reDoS = ReDoS.check(topicRegex, "", params, Option.empty());
            if (reDoS != null) {
                String reDoSType = reDoS.getClass().getSimpleName();
                if (reDoSType.contains("Vulnerable")) {
                    System.out.println("VULNERABLE: The topic regex '" + topicRegex + "' is vulnerable to ReDoS");
                    return 1;
                } else if (reDoSType.contains("Unknown")) {
                    System.out.println("TIMEOUT: The topic regex check timed out after " + timeoutSeconds + " seconds");
                    return 2;
                }
            }
            System.out.println("SAFE: The topic regex '" + topicRegex + "' is safe");
            return 0;
        } catch (Exception e) {
            log.error("Error checking topic regex '{}': {}", topicRegex, e.getMessage(), e);
            System.out.println("ERROR: " + e.getMessage());
            return 3;
        }
    }
}