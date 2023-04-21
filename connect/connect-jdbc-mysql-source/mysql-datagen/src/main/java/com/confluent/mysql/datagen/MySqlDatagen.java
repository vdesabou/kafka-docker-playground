package com.confluent.mysql.datagen;

import com.beust.jcommander.JCommander;
import com.github.javafaker.Faker;
import java.io.IOException;
import java.sql.*;
import java.util.Date;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.apache.logging.log4j.LogManager;

import static java.time.Duration.*;


public class MySqlDatagen {

    private static final Logger log = LogManager.getLogger(MySqlDatagen.class);
    private static final AtomicInteger numTransactions = new AtomicInteger();

    public static void main(String[] args) throws IOException, InterruptedException, ExecutionException {

        InputParams params = new InputParams();
        JCommander jc = new JCommander();
        jc.setProgramName("java -jar <jarFile>");
        jc.addObject(params);
        try {
            jc.parse(args);
            if (params.isHelp()) {
                jc.usage();
                return;
            }
        } catch (Exception e) {
            System.out.println("\n"+e.getMessage() +" \n\n");
            jc.usage();
            return;
        }

        int durationTimeMin = params.getdurationTimeMin();
        ExecutorService invokeTxnPool = Executors.newFixedThreadPool(params.getPoolSize());
        ExecutorService heavyTxnPool = Executors.newSingleThreadExecutor();
        AtomicBoolean finishExecution = new AtomicBoolean();
        MySqlDatabase database = new MySqlDatabase(params);
        Faker faker = new Faker();
        long startTime = new Date().getTime();
        long endTime = startTime + (durationTimeMin*60*1000) + (10*1000);
        log.info("startTime::{}", new Date(startTime));
        log.info("endTime::{}", new Date(endTime));
        for (int i = 0; i < params.getPoolSize() - 1; i++) {
            invokeTxnPool.execute(() -> {
                try (Connection connection = database.getConnection()) {
                    while (!finishExecution.get()) {
                        connection.setAutoCommit(false);
                        PreparedStatement stmt = connection.prepareStatement("insert into team (name, email, last_modified) values (?, ?, NOW())");
                        stmt.setString(1, faker.name().firstName());
                        stmt.setString(2, faker.internet().emailAddress());
                        stmt.executeUpdate();
                        connection.commit();
                        stmt.close();

                        numTransactions.getAndIncrement();
                        stmt.close();
                    }
                } catch (SQLException sqlException) {
                    sqlException.printStackTrace();
                }
            });
        }

        while (true) {
            if (new Date().getTime() > endTime) {
                finishExecution.set(true);
                break;
            }
        }
        log.info("End load test at: {}",new Date());
        log.info("Num Transactions clocked:{}", numTransactions.get());
        System.exit(0);
    }
}
