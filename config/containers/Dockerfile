FROM --platform=linux/arm64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG OPENCODE_VERSION=1.2.27

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    fd-find \
    git \
    gnupg \
    jq \
    less \
    procps \
    python3 \
    python3-pip \
    ripgrep \
    sudo \
    tini \
    unzip \
    wget \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd || true

RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
  && npm cache clean --force

RUN useradd -m -s /bin/bash opencode \
  && mkdir -p /workspace /configurations /data \
  && chown -R opencode:opencode /workspace /configurations /data /home/opencode

USER opencode
WORKDIR /workspace

ENV HOME=/home/opencode
ENV XDG_CONFIG_HOME=/configurations
ENV XDG_DATA_HOME=/data

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
