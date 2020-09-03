FROM ubuntu
RUN apt-get update && \
    apt-get install -y openjdk-8-jdk && \
    apt-get clean all
COPY AMPS.tar /binaries/AMPS.tar
COPY config.xml /
RUN ls -l /
RUN ls -l /binaries
RUN tar xvf /binaries/AMPS.tar --transform='s,AMPS[^/]*/,AMPS/,'
RUN ls -l /

# expose websocket and TCP port (adjust as needed for your AMPS config file)
EXPOSE 9007
EXPOSE 9008

# expose Admin port (adjust as needed for your AMPS config file)
EXPOSE 8085

CMD ["/AMPS/bin/ampServer","config.xml"]