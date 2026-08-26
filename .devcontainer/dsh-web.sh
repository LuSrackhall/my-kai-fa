#!/usr/bin/env bash
# ============================================================
# dsh-web — 在容器内启动 DeepSeek Harness 的 Web UI
#
# 官方命令是 `npx @deepseek-ai/dsh web`;本脚本按容器环境固化参数,
# 并解决一个官方安全限制带来的连通问题:
#
#   dsh 的 web 服务出于安全只允许绑定 127.0.0.1(拒绝 0.0.0.0),
#   但 Docker 的端口映射只能到达容器的网卡地址,够不到容器回环。
#   解法: 用 socat 在容器内开 0.0.0.0:3081 → 转发到 127.0.0.1:3080,
#   宿主机只需映射 13080 → 容器 3081 (见 scripts/start.sh)。
#
# 额外参数原样透传给 `dsh web`,如: dsh-web --port 4000
# 前置: 先执行过 dsh-setup 安装 dsh;镜像内已含 socat
# ============================================================
set -eo pipefail

# ---- 激活 node(nvm)。两个坑都已填:
#   1) 不能在 set -u 下 source nvm.sh;
#   2) nvm.sh 与 NPM_CONFIG_PREFIX 互斥(交互 shell 经 init-env 已设置它),
#      source 前必须 unset;启动服务不需要该变量,不装回。----
export NVM_DIR="/usr/local/share/nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    set +u
    unset NPM_CONFIG_PREFIX
    . "$NVM_DIR/nvm.sh" || true
    nvm use default --silent >/dev/null 2>&1 || true
    set -u
fi

# ---- 补 PATH 找到用户级安装的 dsh(只加路径,不导出前缀变量) ----
export PATH="$HOME/.npm-global/bin:$PATH"

command -v node   >/dev/null 2>&1 || { echo "[dsh-web] 错误: node 不可用" >&2; exit 1; }
command -v dsh    >/dev/null 2>&1 || { echo "[dsh-web] 尚未安装 dsh,请先执行: dsh-setup" >&2; exit 1; }
command -v socat  >/dev/null 2>&1 || { echo "[dsh-web] 错误: 缺少 socat" >&2; exit 1; }

# ---- 已有实例则不重复启动 ----
if ss -tln 2>/dev/null | grep -q ':3080 '; then
    echo "[dsh-web] Web UI 已在运行,浏览器访问宿主侧 http://127.0.0.1:13080"
    exit 0
fi

# ---- 后台拉起 dsh web(绑容器内 127.0.0.1:3080) ----
nohup dsh web --no-open "$@" > /tmp/dsh-web.log 2>&1 &
for _ in $(seq 1 30); do
    ss -tln 2>/dev/null | grep -q ':3080 ' && break
    sleep 1
done
if ! ss -tln 2>/dev/null | grep -q ':3080 '; then
    echo "[dsh-web] 启动失败,日志如下:" >&2
    tail -20 /tmp/dsh-web.log >&2
    exit 1
fi
echo "[dsh-web] Web UI 已就绪,浏览器访问宿主侧 http://127.0.0.1:13080"

# ---- 前台维持转发: 0.0.0.0:3081 → 127.0.0.1:3080 ----
exec socat TCP4-LISTEN:3081,bind=0.0.0.0,fork,reuseaddr TCP4:127.0.0.1:3080
