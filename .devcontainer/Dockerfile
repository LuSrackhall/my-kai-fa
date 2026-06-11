# ============================================================
# 基于微软 Dev Containers Base Ubuntu (multi-arch)
# 文档: https://github.com/devcontainers/images
#
# base:ubuntu 已包含: Ubuntu, Git, curl, wget, vim, jq,
#   vscode 用户 (UID 1000), Oh My Zsh
#
# 架构: linux/amd64 + linux/arm64 双原生支持
#   Docker 自动选择与宿主机匹配的架构。
#   跨架构构建使用 build.sh 的 --platform 参数。
#
# 语言运行时:
#   Node.js — nvm (版本管理器，构建时预装 LTS)
#   Python  — 系统 python3 + pip + venv
#   Go      — 官方二进制 (/usr/local/go)
#   Rust    — rustup (版本管理器)
#
#   不包含: Java, .NET, PHP, Ruby
# ============================================================
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ============================================================
# 系统工具
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \
    fd-find \
    bat \
    htop \
    tmux \
    jq \
    tree \
    unzip \
    zip \
    less \
    man-db \
    build-essential \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Node.js — nvm (版本管理器)
# 构建时预装一个 LTS 作为默认版本
# ============================================================
ENV NVM_DIR=/usr/local/share/nvm
RUN mkdir -p "$NVM_DIR" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts \
    && nvm use --lts \
    && nvm alias default 'lts/*'

# ============================================================
# Python — 系统 python3 + pip + venv
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Go — 官方二进制 (ARG TARGETARCH 自动匹配 arm64/amd64)
# ============================================================
ARG GO_VERSION=1.23.4
ARG TARGETARCH
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH:-amd64}.tar.gz" \
    | tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:$PATH"

# ============================================================
# Rust — rustup (版本管理器)
# ============================================================
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/vscode/.cargo/bin:$PATH"

# ============================================================
# Shell 初始化 — init-env.sh 统一管理所有版本管理器激活
# ============================================================
COPY .devcontainer/init-env.sh /usr/local/bin/init-env.sh
RUN chmod +x /usr/local/bin/init-env.sh
RUN echo 'source /usr/local/bin/init-env.sh' >> /home/vscode/.zshrc \
    && echo 'source /usr/local/bin/init-env.sh' >> /home/vscode/.bashrc

# ============================================================
# Zsh 别名
# ============================================================
RUN echo 'alias ll="ls -alh"' >> /home/vscode/.zshrc \
    && echo 'alias fd="fdfind"' >> /home/vscode/.zshrc \
    && echo 'alias bat="batcat"' >> /home/vscode/.zshrc

USER vscode
WORKDIR /workspaces
