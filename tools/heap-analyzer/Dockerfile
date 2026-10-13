# Runtime of playground debug heap-analyze: Eclipse Memory Analyzer (MAT), run headless.
# Only MAT is baked here; analyze-heap.sh and digest.py are mounted at run time.
FROM eclipse-temurin:21-jre

ARG MAT_VERSION=1.17.0
ARG MAT_BUILD=20260601
ARG MAT_SHA512_X86_64=a4127c587d425cbe7167873fdc1337950ee7c01bf15dd429b6ad3f26e8ba3bbd0aee9a693aff60f25d6068c9e817b1de617ac94c85ece15a48fda17c1b9b12cd
ARG MAT_SHA512_AARCH64=8dc5c85c6f09813826c8bd3d9cf3748020d271e3e446f531fe90698a9800e91c5ad3a87a4c66a2f105dbd5d43d9919434ec2f44391dc03621050cd76f962fe4b

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 unzip curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN set -e; \
    case "$(uname -m)" in \
      x86_64)  arch=x86_64;  sha="$MAT_SHA512_X86_64" ;; \
      aarch64) arch=aarch64; sha="$MAT_SHA512_AARCH64" ;; \
      *) echo "unsupported architecture $(uname -m)"; exit 1 ;; \
    esac; \
    zip="MemoryAnalyzer-${MAT_VERSION}.${MAT_BUILD}-linux.gtk.${arch}.zip"; \
    curl -fsSL -o /tmp/mat.zip "https://download.eclipse.org/mat/${MAT_VERSION}/rcp/${zip}"; \
    echo "${sha}  /tmp/mat.zip" | sha512sum -c -; \
    unzip -q /tmp/mat.zip -d /opt; \
    rm /tmp/mat.zip; \
    ln -s /opt/mat/plugins/org.eclipse.equinox.launcher_*.jar /opt/mat/launcher.jar

ENV MAT_VERSION=${MAT_VERSION}
ENTRYPOINT ["/bin/bash", "/tools/heap-analyzer/analyze-heap.sh"]
