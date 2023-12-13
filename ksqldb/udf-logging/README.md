# KsqlDB UDF Logging examples


## Objective

Showcase how to use loggers in a ksqlDB User Defined Function (aka. UDF) and related flavors (UDAF, UDTF).

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Out of the box Log4j 1 logging
The Java ecosystem is full of Log frameworks (Log4j 1 and 2, logback, etc.).
SLF4J is known log framework abstraction. 
SLF4j defines a high level API and each log framework provide an implementation.
ksqlDB leverages [Log4j 1](https://logging.apache.org/log4j/1.2/manual.html) as logging implementation.

One can use the provided API to add log a message to ksqlDB log output wihout any further configuration.
The following code use `org.slf4j.Logger` and `log.info` to generate a log message.
In the current ksqlDB's log4j config, messages with level info or higher are added to the log (contact your ksqlDB admin to know what's the lowest )log level set in your infrastructure).

```
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
public class FormulaUdfLog4jCustomLoggingLevel {

    public static final Logger log = LoggerFactory.getLogger(FormulaUdfLog4jCustomLoggingLevel.class);

    @Udf(description = "The standard version of the formula with integer parameters.")
    public long formula(@UdfParameter(value = "v1") final int v1, @UdfParameter(value = "v") final int v2) {
        log.debug("V1: {}, V2: {}", v1, v2);
        return (v1 * v2);
    }
}

```

Example of output log:
```
[2021-09-21 08:53:58,941] INFO V1: 2, V2: 3 (com.example.FormulaUdfSimpleLog4jLogging)
[2021-09-21 08:53:58,973] INFO V1: 4, V2: 6 (com.example.FormulaUdfSimpleLog4jLogging)
[2021-09-21 08:53:58,974] INFO V1: 6, V2: 9 (com.example.FormulaUdfSimpleLog4jLogging)
```

## Log4j 1 logging with a custom log level
If you want to have a custom log level for you UDF, then you'll need to add this configuration to ksqlDB's log4j configuration file.
```
log4j.rootLogger=INFO, stdout

log4j.appender.stdout=org.apache.log4j.ConsoleAppender
log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
log4j.appender.stdout.layout.ConversionPattern=[%d] %p %m (%c)%n

# Override the default log level for the UDF logger
log4j.logger.com.example.FormulaUdfLog4jCustomLoggingLevel=DEBUG, stdout
log4j.additivity.com.example.FormulaUdfLog4jCustomLoggingLevel=false
```

Note: 
Addivity is a Log4j 1 concepts permitting to one log message to be handle by multiple log appenders.
With additivity enabled, the UDF debug message will be outputted twice, once via the logger `com.example.FormulaUdfLog4jCustomLoggingLeve` with appender `stdout` and a second time with the UDF's parent logger (rootLogger) which has `stdout` has appender. 
To prevent this duplication, we set the the flag `log4j.additivity.com.example.FormulaUdfLog4jCustomLoggingLevel=false`.

Example of output log:
```
[2021-09-21 08:53:58,973] DEBUG V1: 2, V2: 3 (com.example.FormulaUdfLog4jCustomLoggingLevel)
[2021-09-21 08:53:58,974] DEBUG V1: 4, V2: 6 (com.example.FormulaUdfLog4jCustomLoggingLevel)
[2021-09-21 08:53:58,974] DEBUG V1: 6, V2: 9 (com.example.FormulaUdfLog4jCustomLoggingLevel)
```

## Use a custom Log framework
Let's say you want to use logback as Log framework rather than Log4J for your UDF, then you'll have 3 main point of interests:

1- Add the logback dependency in your UDF JAR
As defined in the [Creating a UDF and UDAFs](https://docs.confluent.io/5.3.2/ksql/docs/developer-guide/udf.html#creating-udf-and-udafs) documentation, each UDF has a classpath isolation.
This means if your UDF has specific dependencies, it's up to you to provide them in your UDF jar.
A jar with its dependencies is named uberJar (or jar "with-dependencies").
This is commonly done by using the Maven assembly or shade plugins (or their Graddle equivalent).

2- Provide a logback configuration file
Since you're not relying on the ksqlDB provided log4j configuration, you need to handle your logger configuration.
Logback can be configure by using a `logback.xml` config file.

3- Remove the Log4j dependencies
Your UDF relies on the `ksql-udf` dependency which embeds a transitive compile dependency on log4j libraries.
```
$ mvn dependency:tree
[INFO] com.example:my-udf:1.0.0
[INFO] \- io.confluent.ksql:ksql-udf:jar:5.4.4:compile
[INFO]    +- org.slf4j:slf4j-api:jar:1.7.26:compile
[INFO]    +- org.slf4j:slf4j-log4j12:jar:1.7.26:compile
[INFO]    +- io.confluent:confluent-log4j:jar:1.2.17-cp2:compile
[INFO]    \- io.confluent:common-utils:jar:5.4.4:compile
```
These log4j depencies will conflict with logback hence need to be removed

You should end up with a similar pom.xml
```
...
    <dependencies>
        <dependency>
            <groupId>io.confluent.ksql</groupId>
            <artifactId>ksql-udf</artifactId>
            <version>${confluent.ksql-udf.version}</version>
            <exclusions>
                <exclusion>
                    <groupId>org.slf4j</groupId>
                    <artifactId>slf4j-log4j12</artifactId>
                </exclusion>
                <exclusion>
                    <groupId>log4j</groupId>
                    <artifactId>log4j</artifactId>
                </exclusion>
                <exclusion>
                    <groupId>io.confluent</groupId>
                    <artifactId>confluent-log4j</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>ch.qos.logback</groupId>
            <artifactId>logback-classic</artifactId>
            <version>${logback.version}</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
        <!-- Package all dependencies as one jar -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-assembly-plugin</artifactId>
                <version>${maven-assembly-plugin.version}</version>
                <configuration>
                    <descriptorRefs>
                        <descriptorRef>jar-with-dependencies</descriptorRef>
                    </descriptorRefs>
                    <archive>                    
                        <manifest>
                            <addClasspath>true</addClasspath>
                            <mainClass>${exec.mainClass}</mainClass>
                        </manifest>
                    </archive>
                </configuration>
                <executions>
                    <execution>
                        <id>assemble-all</id>
                        <phase>package</phase>
                        <goals>
                        <goal>single</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
```

```
    </dependencies>
        <dependency>
            <groupId>ch.qos.logback</groupId>
            <artifactId>logback-classic</artifactId>
            <version>${logback.version}</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
        <!-- Package all dependencies as one jar -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-assembly-plugin</artifactId>
                <version>${maven-assembly-plugin.version}</version>
                <configuration>
                    <descriptorRefs>
                        <descriptorRef>jar-with-dependencies</descriptorRef>
                    </descriptorRefs>
                    <archive>                    
                        <manifest>
                            <addClasspath>true</addClasspath>
                            <mainClass>${exec.mainClass}</mainClass>
                        </manifest>
                    </archive>
                </configuration>
                <executions>
                    <execution>
                        <id>assemble-all</id>
                        <phase>package</phase>
                        <goals>
                        <goal>single</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
...
```

Example of output log:
```
08:53:58.945 [_confluent-ksql-default_query_CSAS_S2_1-cd37ae5c-3201-438d-9b3b-a4caab891c6b-StreamThread-1] INFO  com.example.FormulaUdfCustomLogger - V1: 2, V2: 3
08:53:58.973 [_confluent-ksql-default_query_CSAS_S2_1-cd37ae5c-3201-438d-9b3b-a4caab891c6b-StreamThread-1] INFO  com.example.FormulaUdfCustomLogger - V1: 4, V2: 6
08:53:58.975 [_confluent-ksql-default_query_CSAS_S2_1-cd37ae5c-3201-438d-9b3b-a4caab891c6b-StreamThread-1] INFO  com.example.FormulaUdfCustomLogger - V1: 6, V2: 9
```
