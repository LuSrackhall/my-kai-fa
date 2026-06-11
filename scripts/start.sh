#!/usr/bin/env bash
# ============================================================
# start.sh — 按名启动开发容器
#
# 用法:
#   ./scripts/start.sh <容器名> <宿主机路径>                            首次启动,或进入已有容器
#   ./scripts/start.sh <容器名> <宿主机路径> -f                         强制删除旧容器并新建
#   ./scripts/start.sh <容器名> <宿主机路径> -f --platform linux/amd64  强制重建 + 指定架构
#   ./scripts/start.sh <容器名> <宿主机路径> --platform linux/arm64      指定架构
#
# 示例:
#   ./scripts/start.sh my-project ~/kai-fa/projects/foo
#   ./scripts/start.sh my-project ~/kai-fa/projects/foo -f
#   ./scripts/start.sh playground ~/Desktop/experiment --platform linux/amd64
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
#   │                          -v <指定路径>:/workspaces/<basename> \
#   │                          -v $HOME/kai-fa/projects:/workspaces/projects \
#   │                          -v $HOME/kai-fa/data:/workspaces/data \
#   │                          -v $HOME/.ssh:/home/vscode/.ssh:ro \
#   │                          -v $HOME/.gitconfig:/home/vscode/.gitconfig:ro \
#   │                          -v /var/run/docker.sock:/var/run/docker.sock \
#   │                          --network=host \
#   │                          safe-agent-dev:latest zsh
#   │
#   └─ 使用 Ctrl+D 或 exit 退出容器 Shell
#      (容器保持运行,下次 start.sh <同名> 可直接进入)
#
# 前置条件:
#   - Docker 已安装并运行
#   - 当前工作目录为项目根目录
#   - ~/kai-fa/projects 和 ~/kai-fa/data 目录已创建 (mkdir -p)
#   - ~/.ssh 目录存在
#
# 多容器注意:
#   - 同一镜像可启动任意多个容器,互不干扰
#   - 两个容器可挂载相同宿主机路径 (各自独立的文件视图)
#   - 容器名必须唯一 (Docker 要求)
# ============================================================

set -euo pipefail

# ============================================================
# 常量
# ============================================================
readonly IMAGE_NAME="safe-agent-dev"
readonly IMAGE_TAG="latest"
readonly FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

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
    echo "  $0 <容器名> <宿主机路径>                            启动/进入容器"
    echo "  $0 <容器名> <宿主机路径> -f                         强制重建容器"
    echo "  $0 <容器名> <宿主机路径> --platform linux/amd64      指定架构"
    echo "  $0 <容器名> <宿主机路径> -f --platform linux/amd64   强制重建 + 指定架构"
    echo ""
    echo "示例:"
    echo "  $0 my-project ~/kai-fa/projects/foo"
    echo "  $0 my-project ~/kai-fa/projects/foo -f"
    echo "  $0 my-project ~/kai-fa/projects/foo -f --platform linux/amd64"
}

# ============================================================
# 参数解析
# ============================================================
if [ $# -lt 2 ]; then
    print_usage
    exit 1
fi

CONTAINER_NAME="$1"
HOST_PATH="$2"
FORCE_RECREATE=false
PLATFORM_ARG=""

shift 2

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
            error "未知参数: $1"
            print_usage
            exit 1
            ;;
    esac
done

# 解析宿主机路径为绝对路径
HOST_PATH="$(cd "$HOST_PATH" 2>/dev/null && pwd || true)"
if [ -z "$HOST_PATH" ]; then
    error "宿主机路径不存在或无法访问: $2"
    error "请确认路径正确后再试。"
    exit 1
fi

# 生成容器内挂载目标路径
MOUNT_BASENAME="$(basename "$HOST_PATH")"
CONTAINER_TARGET="/workspaces/${MOUNT_BASENAME}"

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
info "  宿主机路径:  ${HOST_PATH}"
info "  容器内路径:  ${CONTAINER_TARGET}"
echo ""

# 检查固定挂载所需的宿主机目录
REQUIRED_DIRS=(
    "${HOME}/kai-fa/projects"
    "${HOME}/kai-fa/data"
    "${HOME}/.ssh"
)

MISSING_DIRS=()
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ] && [ ! -f "$dir" ]; then
        MISSING_DIRS+=("$dir")
    fi
done

if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
    error "以下宿主机目录不存在:"
    for dir in "${MISSING_DIRS[@]}"; do
        error "  - ${dir}"
    done
    error ""
    error "请先创建所需目录:"
    error "  mkdir -p ~/kai-fa/projects ~/kai-fa/data"
    error ""
    error "容器创建已中止。"
    exit 1
fi

docker run -it \
    --name "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --network=host \
    -v "${HOST_PATH}:${CONTAINER_TARGET}" \
    -v "${HOME}/kai-fa/projects:/workspaces/projects" \
    -v "${HOME}/kai-fa/data:/workspaces/data" \
    -v "${HOME}/.ssh:/home/vscode/.ssh:ro" \
    -v "${HOME}/.gitconfig:/home/vscode/.gitconfig:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
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
    info "  重新进入:  $0 ${CONTAINER_NAME} ${HOST_PATH}"
    info "  删除容器:  docker rm ${CONTAINER_NAME}"
    info "  强制重建:  $0 ${CONTAINER_NAME} ${HOST_PATH} -f"
fi
