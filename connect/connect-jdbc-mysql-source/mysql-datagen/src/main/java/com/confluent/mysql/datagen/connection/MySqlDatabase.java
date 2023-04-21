package com.confluent.mysql.datagen.connection;

import java.sql.*;
import org.apache.logging.log4j.LogManager;


public class MySqlDatabase {

  private static final Logger log = LogManager.getLogger(MySqlDatabase.class);

  private final Connection connection;

  public MySqlDatabase(InputParams params){


    try
    {
        Class.forName("com.mysql.jdbc.Driver");
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
