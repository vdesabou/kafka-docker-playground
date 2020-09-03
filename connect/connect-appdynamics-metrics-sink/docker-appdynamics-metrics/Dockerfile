# Sample Dockerfile for the AppDynamics Standalone Machine Agent
# This is provided for illustration purposes only, for full details
# please consult the product documentation: https://docs.appdynamics.com/

FROM ubuntu:14.04

# Install required packages
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y unzip && \
    apt-get clean

# Install AppDynamics Machine Agent
ENV MACHINE_AGENT_HOME /opt/appdynamics/machine-agent/
ADD machine-agent.zip /tmp/
RUN mkdir -p ${MACHINE_AGENT_HOME} && \
    unzip -oq /tmp/machine-agent.zip -d ${MACHINE_AGENT_HOME} && \
    rm /tmp/machine-agent.zip

# Include start script to configure and start MA at runtime
ADD start-appdynamics ${MACHINE_AGENT_HOME}
ADD log4j.xml ${MACHINE_AGENT_HOME}/conf/logging/
RUN chmod 744 ${MACHINE_AGENT_HOME}/start-appdynamics

# Configure and Run AppDynamics Machine Agent
CMD "${MACHINE_AGENT_HOME}/start-appdynamics"