FROM eclipse-temurin:17-jdk

LABEL maintainer="kafka-docker-playground"
LABEL description="Heap dump analyzer for Java applications"

# Install required tools
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create analysis workspace
WORKDIR /analysis

# Copy analyzer script
COPY analyze-heap.sh /usr/local/bin/analyze-heap
RUN chmod +x /usr/local/bin/analyze-heap

# Default command
ENTRYPOINT ["/usr/local/bin/analyze-heap"]
CMD ["--help"]
