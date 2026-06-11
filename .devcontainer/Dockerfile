# ============================================================
# 基于微软 Dev Containers Universal 镜像
# 文档: https://github.com/devcontainers/images
# 镜像: mcr.microsoft.com/devcontainers/universal:latest
#
# universal 镜像已包含（无需重装）:
#   - Ubuntu 基础系统
#   - Node.js / Python / Go / Rust / Java / .NET / PHP / Ruby
#   - Git / curl / wget / vim / nano / jq / less
#   - vscode 用户 (UID 1000)
#   - Oh My Zsh + 常用插件
# ============================================================
FROM --platform=linux/amd64 mcr.microsoft.com/devcontainers/universal:latest

# ============================================================
# 补充系统工具
# universal 已包含多数常用 CLI，此处仅补遗
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \       
    fd-find \       
    bat \           
    htop \          
    tmux \          
    && rm -rf /var/lib/apt/lists/*
    # RUN apt-get update && apt-get install -y --no-install-recommends \
    #     ripgrep \       
    #     fd-find \       # 高性能文件查找 (fd)
    #     bat \           # 语法高亮 cat 替代 (batcat)
    #     htop \          # 交互式进程监控
    #     tmux \          # 终端复用器
    #     && rm -rf /var/lib/apt/lists/*
# ============================================================
# 补充全局运行时工具
# ============================================================
RUN npm install -g pnpm

# ============================================================
# 用户与 Shell 配置
# universal 镜像默认 vscode 用户, UID 1000
# ============================================================
USER vscode

# Zsh 别名
RUN echo 'alias ll="ls -alh"' >> ~/.zshrc \
    && echo 'alias fd="fdfind"' >> ~/.zshrc \
    && echo 'alias bat="batcat"' >> ~/.zshrc

# 默认工作目录（挂载路径的父目录）
WORKDIR /workspaces
