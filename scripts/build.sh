#!/usr/bin/env bash
# ============================================================
# build.sh — 构建 safe-agent-dev 开发镜像
#
# 用法:
#   ./scripts/build.sh                          自动检测架构
#   ./scripts/build.sh --platform linux/amd64   强制构建 AMD64 版本
#   ./scripts/build.sh --platform linux/arm64   强制构建 ARM64 版本
#
# 说明:
#   基于 .devcontainer/Dockerfile 构建镜像，
#   tag 固定为 safe-agent-dev:latest。
#
#   默认行为:
#     Docker 自动选择与宿主机匹配的原生架构:
#       Apple Silicon (M1/M2/M3)  → linux/arm64
#       Intel Mac / Linux / Win   → linux/amd64
#
#   跨架构场景:
#     --platform linux/amd64  在 ARM Mac 上构建 Rosetta 模拟版本
#     --platform linux/arm64  在 Intel 机器上构建 ARM 版本 (通常不需要)
#
#   此镜像同时被以下入口使用:
#     - VS Code Dev Containers (Cmd+Shift+P → Reopen in Container)
#     - scripts/start.sh (宿主机快速启动)
#
# 前置条件:
#   - Docker 已安装并运行
#   - 当前工作目录为项目根目录
# ============================================================

set -euo pipefail

IMAGE_NAME="safe-agent-dev"
IMAGE_TAG="latest"

# ============================================================
# 参数解析
# ============================================================
PLATFORM_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            if [[ -z "${2:-}" ]]; then
                echo "错误: --platform 需要参数 (如 linux/amd64 或 linux/arm64)"
                exit 1
            fi
            PLATFORM_ARG="--platform $2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--platform linux/amd64|linux/arm64]"
            exit 1
            ;;
    esac
done

# ============================================================
# 构建
# ============================================================
echo "=== 构建镜像: ${IMAGE_NAME}:${IMAGE_TAG} ==="
echo ""
echo "构建上下文: $(pwd)"
echo "Dockerfile:  .devcontainer/Dockerfile"
if [[ -n "${PLATFORM_ARG}" ]]; then
    echo "目标平台:   ${PLATFORM_ARG#--platform }"
else
    echo "目标平台:   自动检测 (Docker 默认)"
fi
echo ""

# shellcheck disable=SC2086
docker build \
    ${PLATFORM_ARG} \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --file .devcontainer/Dockerfile \
    .

echo ""
echo "=== 构建完成 ==="
echo "镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "查看镜像:  docker images ${IMAGE_NAME}"
echo "启动容器:  ./scripts/start.sh <容器名> <宿主机路径>"
