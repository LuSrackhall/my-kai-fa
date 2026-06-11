# ============================================================
# 基于微软 Dev Containers Base Ubuntu 镜像
# 文档: https://github.com/devcontainers/images
# 镜像: mcr.microsoft.com/devcontainers/base:ubuntu
#
# base:ubuntu 镜像已包含:
#   - Ubuntu 基础系统
#   - Git / curl / wget / vim / nano / jq / less
#   - vscode 用户 (UID 1000)
#   - Oh My Zsh + 常用插件
#
# 语言运行时 (Node / Python / Go / Rust) 通过
# devcontainer.json 的 Features 按需安装,不写入镜像。
#
# 架构支持:
#   base:ubuntu 是 multi-arch 镜像,支持 linux/amd64 和 linux/arm64。
#   Docker 自动选择与宿主机匹配的架构,无需 --platform。
#   如需跨架构构建,使用 build.sh 的 --platform 参数。
# ============================================================
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ============================================================
# 补充系统工具
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \       
    fd-find \       
    bat \           
    htop \          
    tmux \          
    && rm -rf /var/lib/apt/lists/*
    # RUN apt-get update && apt-get install -y --no-install-recommends \
    #     ripgrep \       # 高性能代码搜索 (rg)
    #     fd-find \       # 高性能文件查找 (fd)
    #     bat \           # 语法高亮 cat 替代 (batcat)
    #     htop \          # 交互式进程监控
    #     tmux \          # 终端复用器
    #     && rm -rf /var/lib/apt/lists/*

# ============================================================
# 用户与 Shell 配置
# base:ubuntu 镜像默认 vscode 用户, UID 1000
# ============================================================
USER vscode

# Zsh 别名
RUN echo 'alias ll="ls -alh"' >> ~/.zshrc \
    && echo 'alias fd="fdfind"' >> ~/.zshrc \
    && echo 'alias bat="batcat"' >> ~/.zshrc

# 默认工作目录（挂载路径的父目录）
WORKDIR /workspaces
