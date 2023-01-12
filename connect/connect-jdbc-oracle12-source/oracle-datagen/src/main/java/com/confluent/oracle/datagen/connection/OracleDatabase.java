package com.confluent.oracle.datagen.connection;

import com.confluent.oracle.datagen.domain.InputParams;
import oracle.ucp.UniversalConnectionPoolAdapter;
import oracle.ucp.UniversalConnectionPoolException;
import oracle.ucp.admin.UniversalConnectionPoolManager;
import oracle.ucp.admin.UniversalConnectionPoolManagerImpl;
import oracle.ucp.jdbc.PoolDataSource;
import oracle.ucp.jdbc.PoolDataSourceFactory;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.logging.Level;

public class OracleDatabase {

  private final static String DATA_SOURCE_CLASS = "oracle.jdbc.pool.OracleDataSource";

  private final static  String URL = "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=%s)(PORT=%d))(CONNECT_DATA=(%s=%s)))";

  private static final Logger log = LogManager.getLogger(OracleDatabase.class);

  private final  UniversalConnectionPoolManager poolManager;
  private final String CONNECTION_POOL_NAME = "oracle-cdc-connection-pool";


  private final PoolDataSource ds;

  public OracleDatabase(InputParams params){
    this.ds = PoolDataSourceFactory.getPoolDataSource();
    try {

      ds.setConnectionFactoryClassName(DATA_SOURCE_CLASS);
      String connectionStr = String.format(URL,params.getHost(),params.getPort(),params.getSidOrServerName(),
          params.getSidOrServerNameVal());
      log.debug("Connection String used for connection {}", connectionStr);
      ds.setURL(connectionStr);
      ds.setUser(params.getUserName());
      ds.setPassword(params.getPassword());
      ds.setConnectionFactoryProperty("driverType","thin");
      ds.setNetworkProtocol("tcp");
      ds.setConnectionPoolName(CONNECTION_POOL_NAME);
      ds.setInitialPoolSize(1);

      ds.setMinPoolSize(1);
      ds.setMaxPoolSize(params.getPoolSize());
      ds.setValidateConnectionOnBorrow(true);
      ds.setLoginTimeout(0);
      ds.setAbandonedConnectionTimeout(0);
      poolManager = UniversalConnectionPoolManagerImpl.getUniversalConnectionPoolManager();
      poolManager.setLogLevel(Level.INFO);
      this.poolManager.createConnectionPool((UniversalConnectionPoolAdapter) ds);
    } catch (SQLException | UniversalConnectionPoolException e) {
      log.error("Unable to initialize db ", e);
      throw new RuntimeException(e);
    }
  }


  public Connection getConnection() throws SQLException {
    return ds.getConnection();
  }


  public void recycleConnections() throws UniversalConnectionPoolException {
    poolManager.recycleConnectionPool(CONNECTION_POOL_NAME);
  }

}
