#!/usr/bin/env bash
# ============================================================
# init-env.sh — 统一的 Shell 环境初始化
#
# 被 ~/.zshrc 和 ~/.bashrc 自动 source。
# 同时被 devcontainer.json 的 postCreateCommand 调用。
#
# 确保所有版本管理器在新 Shell 中正确激活。
# 幂等设计: 重复 source 安全。
# ============================================================

# ---- nvm (Node.js 版本管理器) ----
export NVM_DIR="/usr/local/share/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ---- Go ----
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# ---- Rust (rustup + cargo) ----
[ -s "$HOME/.cargo/env" ] && \. "$HOME/.cargo/env"

# ---- npm 用户级全局前缀 (dsh 等全局 CLI 安装于此) ----
# dsh 通过 dsh-setup 安装到这里;容器重建后重跑 dsh-setup 即可恢复。
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

# ---- Git 身份配置持久化 (存放在交互区,容器重建不丢) ----
# 首次配置(容器内执行):
#   git config --file /workspaces/dsh-safe/git/gitconfig user.name  "你的名字"
#   git config --file /workspaces/dsh-safe/git/gitconfig user.email "你的邮箱"
# 存在后自动启用,替代宿主机 ~/.gitconfig(不再挂载,避免敏感信息进容器)。
if [ -f /workspaces/dsh-safe/git/gitconfig ]; then
    export GIT_CONFIG_GLOBAL=/workspaces/dsh-safe/git/gitconfig
fi
