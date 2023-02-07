package com.confluent.oracle.datagen;

import com.beust.jcommander.JCommander;
import com.confluent.oracle.datagen.connection.OracleDatabase;
import com.confluent.oracle.datagen.domain.InputParams;
import oracle.ucp.UniversalConnectionPoolException;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.sql.*;
import java.time.Duration;
import java.util.Date;
import java.util.List;
import java.util.TimerTask;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import com.github.javafaker.Faker;
import static java.time.Duration.*;


public class OracleDatagen {

    private static final Logger log = LogManager.getLogger(OracleDatagen.class);
    private static final AtomicInteger numTransactions = new AtomicInteger();

    public static void main(String[] args) throws IOException, UniversalConnectionPoolException, InterruptedException, ExecutionException {

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
        OracleDatabase database = new OracleDatabase(params);
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
                        PreparedStatement stmt = connection.prepareStatement("insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values (?, ?, ?, ?, ?, ?)");
                        stmt.setString(1, faker.name().firstName());
                        stmt.setString(2, faker.name().lastName());
                        stmt.setString(3, faker.internet().emailAddress());
                        stmt.setString(4, faker.name().prefix());
                        stmt.setString(5, faker.color().name());
                        stmt.setString(6, faker.lorem() .sentence());
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

        // for (int i = 0; i < params.getPoolSize() - 1; i++) {
        //     heavyTxnPool.submit(() -> {
        //         try (Connection connection = database.getConnection()) {
        //             connection.setAutoCommit(false);
        //             PreparedStatement stmt = connection.prepareStatement("insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values (?, ?, ?, ?, ?, ?)");
        //             stmt.setString(1, "Rica");
        //             stmt.setString(2, "Blaisdell");
        //             stmt.setString(3, "rblaisdell0@rambler.ru");
        //             stmt.setString(4, "Female");
        //             stmt.setString(5, "bronze");
        //             stmt.setString(6, "Universal optimal hierarchy");
        //             stmt.executeUpdate();
        //             // log.info("Sleep before committing");
        //             // Thread.sleep(ofMinutes(durationTimeMin).toMillis());
        //             connection.rollback();
        //             numTransactions.getAndIncrement();
        //             stmt.close();
        //         } catch (SQLException sqlException) {
        //             sqlException.printStackTrace();
        //         }
        //     });
        // }

        while (true) {
            if (new Date().getTime() > endTime) {
                finishExecution.set(true);
                break;
            }
        }
        log.info("End load test at: {}",new Date());
        log.info("Num Transactions clocked:{}", numTransactions.get());
        database.recycleConnections();
        System.exit(0);
    }

}
