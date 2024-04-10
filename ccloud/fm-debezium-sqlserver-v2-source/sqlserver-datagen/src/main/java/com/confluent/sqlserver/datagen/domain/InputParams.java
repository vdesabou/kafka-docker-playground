package com.confluent.sqlserver.datagen.domain;
import com.beust.jcommander.Parameter;

public class InputParams {

  @Parameter(
      names = {"--username","-u"},
      description = "Connection Username",
      required = false
  )
   String userName;

    @Parameter(
      names = {"--password"},
      description = "Connection Password",
      password = true,
      required = false
  )
   String password;

  @Parameter(
      names = {"--connectionUrl","-s"},
      description = "jdbc url to us",
      required = true
  )
   String connectionUrl;

  @Parameter(
      names = "--durationTimeMin",
      description = "Duration of the test in minutes",
      required = false
  )
   int durationTimeMin=4;

  @Parameter(
      names = "--maxPoolSize",
      description = "maximum size of connection pool",
      required = false
  )
  int poolSize=5;


  @Parameter(names = {"--help","-h"}, help = true)
   boolean help;

    public String getUserName() {
        return userName;
    }

    public String getPassword() {
        return password;
    }

    public String getConnectionUrl() {
        return connectionUrl;
    }

    public int getPoolSize() {
        return poolSize;
    }

    public int getdurationTimeMin() {
        return durationTimeMin;
    }

    public boolean isHelp() {
        return help;
    }

}
