# Capture Authentication Logs with Confluent For Kubernetes

## Objective
This example is the Confluent For Kubernetes variant of [Capturing Authentication Logs](../../other/capture-authentication-logs/)

## Details of what the script is doing

The Kubernetes manifest defines a Confluent Platform environment with `ConfigOverrides` to change the `Selector` log level from INFO to DEBUG.

The manifest deploy 2 pods running `kafka-producer-perf-test`, one with valid credentials, another with bad credentials.

The script ends up by filtering the Success/Failures authentication logs and formatting them to display the incoming IP and (when possible) the userId.