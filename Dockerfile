FROM debian:bookworm-slim

ARG DUCKDB_VERSION=1.1.3
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && case "${TARGETARCH}" in \
         amd64) DUCKDB_ARCH=amd64 ;; \
         arm64) DUCKDB_ARCH=aarch64 ;; \
         *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
       esac \
    && curl -L https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${DUCKDB_ARCH}.zip -o /tmp/duckdb.zip \
    && unzip /tmp/duckdb.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/duckdb \
    && rm /tmp/duckdb.zip \
    && apt-get purge -y unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENTRYPOINT ["duckdb"]
