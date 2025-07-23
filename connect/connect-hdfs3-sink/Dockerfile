# Use the official image as a base
FROM apache/hadoop:3.3.6

# Switch to root user to modify the file
USER root

# Apply the fix from the JIRA ticket using sed to correct the Python script
RUN sed -i 's/for key, val in props:/for key, val in props.items():/' /opt/transformation.py

# We will NOT switch back to USER hadoop here, so the container starts as root.