package com.confluent.postgres.datagen.connection;

import com.confluent.postgres.datagen.domain.InputParams;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.sql.*;
import java.util.logging.Level;

public class PostgresDatabase {

  private static final Logger log = LogManager.getLogger(PostgresDatabase.class);

  private final Connection connection;

  public PostgresDatabase(InputParams params){


    try
    {
        Class.forName("org.postgresql.Driver");
    }  catch (Exception e)
    {
        log.error("Error loading JDBC driver {}", e);
        throw new RuntimeException(e);
    }

    try
    {
        connection = DriverManager.getConnection(params.getConnectionUrl());
    }  catch (SQLException e)
    {
        log.error("Error connecting to the database with url {} {}", params.getConnectionUrl(), e);
        throw new RuntimeException(e);
    }
  }


  public Connection getConnection() throws SQLException {
    return connection;
  }
}
