FROM ubuntu:24.04

LABEL maintainer="Antigravity Community"
LABEL description="Automated builder and repository watcher for Google Antigravity .deb packages"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ARCH=amd64 \
    PRODUCT=all \
    BUILD_MODE=all \
    CHECK_INTERVAL=3600 \
    OUTPUT_DIR=/output \
    HTTP_PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
    dpkg-dev \
    binutils \
    curl \
    python3 \
    tar \
    gzip \
    xz-utils \
    ca-certificates \
    file \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /scripts /output

COPY scripts/ /scripts/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /scripts/*.sh /scripts/*.py

VOLUME ["/output"]
EXPOSE 8080

WORKDIR /output

ENTRYPOINT ["/entrypoint.sh"]
CMD ["watch"]
