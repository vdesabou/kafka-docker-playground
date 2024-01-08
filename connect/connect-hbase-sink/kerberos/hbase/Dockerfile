FROM lenchv/hbase-base:hadoop-2.7.4-hbase-2.2.3

COPY ./hadoop/* $HADOOP_CONF_DIR/
COPY ./hbase/* $HBASE_CONF_DIR/
COPY ./zoo/* $ZOO_HOME/conf/

ENV CORE_CONF_fs_defaultFS=hdfs://_HOST:9000

RUN echo "export HADOOP_OPTS=\"\$HADOOP_OPTS -Djavax.net.debug=ssl -Dsun.security.krb5.debug=\"" >> $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
RUN mkdir -p /hbase/staging && chmod 711 /hbase/staging

WORKDIR $HBASE_HOME

COPY generateSsl.sh /generateSsl.sh
COPY startup.sh /startup.sh
RUN chmod +x /startup.sh
RUN chmod +x /generateSsl.sh

CMD ["/startup.sh"]