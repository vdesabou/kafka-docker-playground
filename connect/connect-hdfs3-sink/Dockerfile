FROM apache/hadoop:3.3.6

# Switch to root user to modify the file
USER root

# Edit transformation.py to fix the issue described in HADOOP-17436
RUN sed -i 's/for key, val in props:/for key, val in props.items():/' /opt/transformation.py
