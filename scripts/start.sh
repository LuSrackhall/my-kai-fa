#!/usr/bin/env bash
# ============================================================
# start.sh — 按名启动开发容器
#
# 用法:
#   ./scripts/start.sh <容器名>                          启动/进入容器 (只挂长久交互区)
#   ./scripts/start.sh <容器名> <宿主机路径>              额外挂载一个专属工作区
#   ./scripts/start.sh <容器名> [宿主机路径] -f           强制删除旧容器并新建
#   ./scripts/start.sh <容器名> [宿主机路径] -f --platform linux/amd64  强制重建 + 指定架构
#
# 示例:
#   ./scripts/start.sh main                                # 日常入口: 只挂 dsh-safe 交互区
#   ./scripts/start.sh proj-a /Volumes/SSD980/dsh-safe/foo # 额外把 foo 挂为本次主目录
#   ./scripts/start.sh main -f                             # 环境搞脏时重置容器
#
# 长久交互区 (--):
#   宿主机路径取环境变量 DSH_SAFE_DIR,未设置时回退 ~/dsh-safe。
#   它始终挂载到容器内 /workspaces/dsh-safe,是容器可见的唯一宿主目录;
#   dsh 的配置/会话状态也持久化在这里,容器重建不丢失。
#
# 安全模型:
#   - 不挂载 docker.sock (宿主 Docker 总开关,等于隔离后门)
#   - 不挂载 ~/.ssh / ~/.gitconfig (只读防删不防读)
#   - 不使用 --network=host,仅映射 127.0.0.1:13080 → 容器 3080 (dsh web GUI;
#     宿主侧换号是为了避开宿主机自身 dsh 占用的 3080)
#
# 架构说明 (--platform):
#   默认: Docker 自动选择与宿主机匹配的原生架构。
#     Apple Silicon Mac  → linux/arm64 (原生性能)
#     Intel Mac / Linux  → linux/amd64 (原生性能)
#     Windows (WSL2)     → linux/amd64 (原生性能)
#
#   跨架构:
#     --platform linux/amd64  在 ARM Mac 上通过 Rosetta 2 运行 amd64 容器
#     --platform linux/arm64  在 Intel 机器上运行 arm64 容器 (通常不需要)
#
#   --platform 会透传给 build.sh,仅在需要构建镜像时生效。
#   已有容器不受 --platform 影响,需配合 -f 先删后建。
#
# 行为:
#   ┌─ 检查镜像 safe-agent-dev:latest 是否存在
#   │   └─ 不存在 → 自动调用 scripts/build.sh [--platform ...] 构建
#   │
#   ├─ 检查容器 <容器名> 是否已存在 (docker ps -a --filter name=...)
#   │   │
#   │   ├─ 存在 且 未传 -f
#   │   │   ├─ 运行中     → docker exec -it <容器名> zsh (进入)
#   │   │   └─ 已停止     → docker start <容器名> && docker exec -it <容器名> zsh
#   │   │
#   │   ├─ 存在 且 传了 -f
#   │   │   └─ 强制删除   → docker rm -f <容器名> → 跳到「创建新容器」
#   │   │
#   │   └─ 不存在
#   │       └─ 创建新容器 → docker run -it --name <容器名> \
#   │                          -p 127.0.0.1:13080:3080 \
#   │                          -v ${DSH_SAFE_DIR:-~/dsh-safe}:/workspaces/dsh-safe \
#   │                          [-v <指定路径>:/workspaces/<basename>] \
#   │                          safe-agent-dev:latest zsh
#   │
#   └─ 使用 Ctrl+D 或 exit 退出容器 Shell
#      (容器保持运行,下次 start.sh <同名> 可直接进入)
#
# 前置条件:
#   - Docker 已安装并运行
#   - 交互区目录存在 (缺失时本脚本会自动创建)
#
# 多容器注意:
#   - 同一镜像可启动任意多个容器,互不干扰
#   - 注意: 多个容器共享同一交互区时,彼此可见区内全部项目
#     ("容器间二次隔离"不属于本设计目标)
#   - 同一宿主机端口 3080 只能被一个运行中的容器占用,
#     同时跑多个容器时,后者需自行调整 -p 映射或仅保留一个
#   - 容器名必须唯一 (Docker 要求)
# ============================================================

set -euo pipefail

# ============================================================
# 常量
# ============================================================
readonly IMAGE_NAME="safe-agent-dev"
readonly IMAGE_TAG="latest"
readonly FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# dsh web GUI 端口: 容器内固定 3080;宿主机侧用 13080 ——
# 避开宿主机自身 dsh 已占用的 127.0.0.1:3080,两者互不干扰
readonly DSH_GUI_CONTAINER_PORT=3080
readonly DSH_GUI_HOST_PORT=13080

# 长久交互区: 环境变量优先,回退 ~/dsh-safe
SAFE_DIR="${DSH_SAFE_DIR:-${HOME}/dsh-safe}"

# 颜色输出
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'

# ============================================================
# 工具函数
# ============================================================
info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; }

print_usage() {
    echo "用法:"
    echo "  $0 <容器名>                          启动/进入容器 (只挂长久交互区)"
    echo "  $0 <容器名> <宿主机路径>              额外挂载一个专属工作区"
    echo "  $0 <容器名> [宿主机路径] -f           强制重建容器"
    echo "  $0 <容器名> [宿主机路径] --platform linux/amd64  指定架构"
    echo ""
    echo "环境变量:"
    echo "  DSH_SAFE_DIR  长久交互区路径 (默认 ~/dsh-safe)"
    echo ""
    echo "示例:"
    echo "  $0 main"
    echo "  $0 proj-a /Volumes/SSD980/dsh-safe/foo"
    echo "  $0 main -f"
}

# ============================================================
# 参数解析 — <容器名> 必填, [宿主机路径] 可选, 其后跟开关
# ============================================================
if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

CONTAINER_NAME="$1"
shift

HOST_PATH=""
FORCE_RECREATE=false
PLATFORM_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            FORCE_RECREATE=true
            shift
            ;;
        --platform)
            if [[ -z "${2:-}" ]]; then
                error "--platform 需要参数 (如 linux/amd64 或 linux/arm64)"
                exit 1
            fi
            PLATFORM_ARG="--platform $2"
            shift 2
            ;;
        *)
            if [ -z "$HOST_PATH" ]; then
                HOST_PATH="$1"
                shift
            else
                error "未知参数: $1"
                print_usage
                exit 1
            fi
            ;;
    esac
done

# ============================================================
# 解析长久交互区路径 (真实绝对路径,兼容软链)
# ============================================================
if [ ! -d "$SAFE_DIR" ]; then
    info "交互区目录不存在,自动创建: ${SAFE_DIR}"
    mkdir -p "$SAFE_DIR"
fi
SAFE_DIR="$(cd "$SAFE_DIR" && pwd)"

# 可选的专属工作区路径解析
EXTRA_MOUNT_ARGS=()
if [ -n "$HOST_PATH" ]; then
    HOST_PATH="$(cd "$HOST_PATH" 2>/dev/null && pwd || true)"
    if [ -z "$HOST_PATH" ]; then
        error "宿主机路径不存在或无法访问"
        exit 1
    fi
    MOUNT_BASENAME="$(basename "$HOST_PATH")"
    EXTRA_MOUNT_ARGS=(-v "${HOST_PATH}:/workspaces/${MOUNT_BASENAME}")
fi

# ============================================================
# 检查镜像是否存在,不存在则自动构建
# ============================================================
if ! docker image inspect "${FULL_IMAGE}" > /dev/null 2>&1; then
    warn "镜像 ${FULL_IMAGE} 不存在,正在自动构建..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    # shellcheck disable=SC2086
    "${SCRIPT_DIR}/build.sh" ${PLATFORM_ARG}
    success "镜像构建完成"
fi

# ============================================================
# 强制重建: 删除已有容器
# ============================================================
if [ "$FORCE_RECREATE" = true ]; then
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "强制重建模式: 删除已有容器 ${CONTAINER_NAME}..."
        docker rm -f "${CONTAINER_NAME}" > /dev/null
        success "旧容器已删除"
    else
        info "强制重建模式: 容器 ${CONTAINER_NAME} 不存在,直接创建新容器"
    fi
fi

# ============================================================
# 检查容器是否已存在
# ============================================================
EXISTING_CONTAINER=$(docker ps -a --format '{{.Names}}' --filter "name=^${CONTAINER_NAME}$" 2>/dev/null || true)

if [ -n "$EXISTING_CONTAINER" ]; then
    # 容器已存在
    CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)

    if [ "$CONTAINER_STATUS" = "running" ]; then
        info "容器 ${CONTAINER_NAME} 正在运行,正在进入..."
    else
        info "容器 ${CONTAINER_NAME} 已停止,正在启动..."
        docker start "${CONTAINER_NAME}" > /dev/null
        success "容器已启动"
    fi

    # 进入容器
    docker exec -it "${CONTAINER_NAME}" zsh
    exit 0
fi

# ============================================================
# 创建新容器
# ============================================================
info "创建新容器: ${CONTAINER_NAME}"
info "  长久交互区:  ${SAFE_DIR} → /workspaces/dsh-safe"
if [ -n "$HOST_PATH" ]; then
    info "  专属工作区:  ${HOST_PATH} → /workspaces/${MOUNT_BASENAME}"
fi
echo ""

docker run -it \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    -p "127.0.0.1:${DSH_GUI_HOST_PORT}:${DSH_GUI_CONTAINER_PORT}" \
    -v "${SAFE_DIR}:/workspaces/dsh-safe" \
    ${EXTRA_MOUNT_ARGS[@]+"${EXTRA_MOUNT_ARGS[@]}"} \
    "${FULL_IMAGE}" \
    zsh

# ============================================================
# 容器退出后的处理
# ============================================================
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    warn "容器退出码: ${EXIT_CODE}"
    info "容器 ${CONTAINER_NAME} 可能已停止。"
    info "使用以下命令重新进入或删除:"
    info "  重新进入:  $0 ${CONTAINER_NAME}"
    info "  删除容器:  docker rm ${CONTAINER_NAME}"
    info "  强制重建:  $0 ${CONTAINER_NAME} -f"
fi
