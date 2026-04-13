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

# Copy analyzer scripts
COPY analyze-heap.sh /usr/local/bin/analyze-heap
COPY parse_hprof.py /usr/local/bin/parse_hprof.py
RUN chmod +x /usr/local/bin/analyze-heap && \
    chmod +x /usr/local/bin/parse_hprof.py

# Default command
ENTRYPOINT ["/usr/local/bin/analyze-heap"]
CMD ["--help"]
