#!/bin/bash

function replace_host() {
	sed -i "s/_HOST/$(hostname -f)/g" $1
	echo "Host replaced: $1"
}

# generate ssl
/generateSsl.sh

# Replace hostname

replace_host $HBASE_CONF_DIR/hbase-client.jaas
replace_host $HBASE_CONF_DIR/hbase-server.jaas
replace_host $HBASE_CONF_DIR/hbase-site.xml
replace_host $ZOO_HOME/conf/zookeeper-client.jaas
replace_host $ZOO_HOME/conf/zookeeper-server.jaas
replace_host $HADOOP_CONF_DIR/core-site.xml
replace_host $HADOOP_CONF_DIR/hdfs-site.xml
replace_host $HADOOP_CONF_DIR/yarn-site.xml
replace_host $HADOOP_CONF_DIR/mapred-site.xml

# Start up hadoop and zookeeper
$HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
$HADOOP_PREFIX/bin/hdfs --config $HADOOP_CONF_DIR namenode -format
$HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR start namenode
$HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR start datanode
$HADOOP_PREFIX/sbin/start-yarn.sh
$HADOOP_PREFIX/sbin/mr-jobhistory-daemon.sh start historyserver
$ZOO_HOME/bin/zkServer.sh start

# Create hbase user and /hbase directory in the hdfs
printf $KRB_ROOT_PASSWORD | kinit root@KERBEROS.SERVER
adduser hbase
groupadd hadoop
usermod -a -G hadoop hbase
hdfs dfs -mkdir /hbase
hdfs dfs -chown -R hbase:hadoop /hbase
hdfs dfs -chown -R hbase:hadoop /tmp
kdestroy

# Start up Hbase and REST API Server
$HBASE_HOME/bin/start-hbase.sh
$HBASE_HOME/bin/hbase-daemon.sh start rest

# Show hbase logs
tail -f $HBASE_HOME/logs/*.log
