package com.confluent.oracle.datagen.domain;
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
      names = {"--sidOrServerName","-s"},
      description = "Oracle connection sid or servername (pdb)",
      required = false
  )
   String sidOrServerName;


  @Parameter(
      names = {"--sidOrServerNameVal","-v"},
      description = "Value for oracle connection sid or servername (pdb)",
      required = false
  )
  String sidOrServerNameVal;

  @Parameter(
      names = {"--host"},
      description = "oracleHostname  for connecting",
      required = false
  )
   String host="localhost";


  @Parameter(
      names = {"--port"},
      description = "oracleHostname  for connecting",
      required = false
  )
  int port = 1521;

  @Parameter(
      names = "--durationTimeMin",
      description = "Seconds to wait before transaction is committed",
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

    public String getSidOrServerName() {
        return sidOrServerName;
    }

    public String getSidOrServerNameVal() {
        return sidOrServerNameVal;
    }

    public String getHost() {
        return host;
    }

    public int getPort() {
        return port;
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
