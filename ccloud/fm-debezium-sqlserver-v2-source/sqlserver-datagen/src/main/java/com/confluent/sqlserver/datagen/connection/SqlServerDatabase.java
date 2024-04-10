package com.confluent.sqlserver.datagen.connection;

import com.confluent.sqlserver.datagen.domain.InputParams;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.sql.*;
import java.util.logging.Level;

public class SqlServerDatabase {

  private static final Logger log = LogManager.getLogger(SqlServerDatabase.class);

  private final Connection connection;

  public SqlServerDatabase(InputParams params){


    try
    {
        Class.forName("com.microsoft.sqlserver.jdbc.SQLServerDriver");
    }  catch (Exception e)
    {
        log.error("Error loading JDBC driver {}", e);
        throw new RuntimeException(e);
    }

    try
    {
        connection = DriverManager.getConnection(params.getConnectionUrl(), params.getUserName(), params.getPassword());
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
