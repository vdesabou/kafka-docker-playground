package com.confluent.mysql.datagen.domain;
import com.beust.jcommander.Parameter;

public class InputParams {

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
