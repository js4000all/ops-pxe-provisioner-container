FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl coreutils libarchive-tools \
    && rm -rf /var/lib/apt/lists/*
COPY prepare.sh /usr/local/bin/prepare
RUN chmod +x /usr/local/bin/prepare
ENTRYPOINT ["/usr/local/bin/prepare"]
