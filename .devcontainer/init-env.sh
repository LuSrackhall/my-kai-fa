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
