#!/usr/bin/env bash
# ============================================================
# build.sh — 构建 safe-agent-dev 开发镜像
#
# 用法:
#   ./scripts/build.sh
#
# 说明:
#   基于 .devcontainer/Dockerfile 构建镜像，
#   tag 固定为 safe-agent-dev:latest。
#
#   此镜像同时被以下入口使用:
#     - VS Code Dev Containers (Cmd+Shift+P → Reopen in Container)
#     - scripts/start.sh (宿主机快速启动)
#
#   对 Dockerfile 或 devcontainer.json 做任何修改后，
#   建议重新执行本脚本以更新镜像。
#
# 前置条件:
#   - Docker 已安装并运行
#   - 当前工作目录为项目根目录
# ============================================================

set -euo pipefail

IMAGE_NAME="safe-agent-dev"
IMAGE_TAG="latest"

echo "=== 构建镜像: ${IMAGE_NAME}:${IMAGE_TAG} ==="
echo ""
echo "构建上下文: $(pwd)"
echo "Dockerfile:  .devcontainer/Dockerfile"
echo ""

docker build \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --file .devcontainer/Dockerfile \
    .

echo ""
echo "=== 构建完成 ==="
echo "镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "查看镜像:  docker images ${IMAGE_NAME}"
echo "启动容器:  ./scripts/start.sh <容器名> <宿主机路径>"
