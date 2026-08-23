#!/usr/bin/env bash
# ============================================================
# dsh-setup — 安装/更新 DeepSeek Harness (dsh) 的统一入口
#
# 设计原则: 固化"命令"而非"版本"——每次执行都安装最新版,
# 容器内已装过的版本重复执行即原地更新。
#
# 安装位置: $HOME/.npm-global (用户级 npm 前缀,无需 root;
# 由 init-env.sh 注入 PATH)。容器重建后重跑本命令即可恢复。
#
# 用法(容器内): dsh-setup
# ============================================================
set -euo pipefail

export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.npm-global}"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

echo "[dsh-setup] 安装/更新 @deepseek-ai/dsh ..."
npm install -g "@deepseek-ai/dsh@latest"

if command -v dsh >/dev/null 2>&1; then
    echo "[dsh-setup] 完成 → $(command -v dsh)"
    dsh --version 2>/dev/null || true
else
    echo "[dsh-setup] 警告: dsh 不在 PATH 中。" >&2
    echo "            请重开 Shell 或执行: source /usr/local/bin/init-env.sh" >&2
    exit 1
fi
