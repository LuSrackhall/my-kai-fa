# Dev Container 开发环境 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建基于微软 Dev Containers Universal 镜像的自定义开发容器环境，包含 Dockerfile、devcontainer.json、构建/启动脚本及使用文档。

**Architecture:** 5 个独立文件。`.devcontainer/Dockerfile` 定义镜像，`.devcontainer/devcontainer.json` 配置 VS Code 集成，`scripts/build.sh` 和 `scripts/start.sh` 提供 CLI 入口，`README.md` 汇总使用说明。所有文件共享同一个镜像 tag `safe-agent-dev:latest`。

**Tech Stack:** Docker, Bash, JSONC (VS Code Dev Containers)

---

### Task 1: 创建 Dockerfile

**Files:**
- Create: `.devcontainer/Dockerfile`

- [ ] **Step 1: 创建目录并写入 Dockerfile**

```bash
mkdir -p .devcontainer
```

```dockerfile
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
FROM mcr.microsoft.com/devcontainers/universal:latest

# ============================================================
# 补充系统工具
# universal 已包含多数常用 CLI，此处仅补遗
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \       # 高性能代码搜索 (rg)
    fd-find \       # 高性能文件查找 (fd)
    bat \           # 语法高亮 cat 替代 (batcat)
    htop \          # 交互式进程监控
    tmux \          # 终端复用器
    && rm -rf /var/lib/apt/lists/*

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
```

- [ ] **Step 2: 验证 Dockerfile 语法**

```bash
docker build --dry-run --file .devcontainer/Dockerfile . 2>&1 || true
```

> 注：`--dry-run` 在某些 Docker 版本不可用。若报 "unknown flag"，改用 `docker build --no-cache --file .devcontainer/Dockerfile . 2>&1 | head -5` 验证构建能启动（Ctrl+C 中断即可，无需完整构建）。

---

### Task 2: 创建 devcontainer.json

**Files:**
- Create: `.devcontainer/devcontainer.json`

- [ ] **Step 1: 写入 devcontainer.json**

```jsonc
{
  // ============================================================
  // 容器名称 — 在 VS Code 左下角显示
  // ============================================================
  "name": "Safe Agent Dev",

  // ============================================================
  // 镜像构建 — 使用项目本地的 Dockerfile
  // context: ".." 将构建上下文设为项目根目录
  // ============================================================
  "build": {
    "dockerfile": "Dockerfile",
    "context": ".."
  },

  // ============================================================
  // 固定挂载点
  //
  // ${localEnv:HOME} 跨平台解析:
  //   macOS:      /Users/<用户名>
  //   Linux:      /home/<用户名>
  //   Windows:    /c/Users/<用户名>（WSL2 下等同于 Linux）
  //
  // mount 类型说明:
  //   type=bind               直接映射宿主机路径
  //   consistency=cached      宿主主机读写一致,容器内可缓存(性能优化)
  //   readonly                只读挂载,防止误修改/删除
  //
  // 路径不存在的处理:
  //   Docker 会直接报错并拒绝启动容器。
  //   请确保宿主机对应路径已存在。可用以下命令创建:
  //     mkdir -p ~/kai-fa/projects ~/kai-fa/data
  // ============================================================
  "mounts": [

    // ① 项目代码目录 → /workspaces/projects
    //    macOS:       /Users/<用户名>/kai-fa/projects
    //    Linux:       /home/<用户名>/kai-fa/projects
    //    Windows:     /c/Users/<用户名>/kai-fa/projects
    //    作用: 存放所有项目的代码仓库。
    //         容器内可同时访问多个项目,无需重复挂载。
    //         可手动编辑此路径以匹配你的实际目录结构。
    "source=${localEnv:HOME}/kai-fa/projects,target=/workspaces/projects,type=bind,consistency=cached",

    // ② 数据目录 → /workspaces/data
    //    macOS:       /Users/<用户名>/kai-fa/data
    //    Linux:       /home/<用户名>/kai-fa/data
    //    Windows:     /c/Users/<用户名>/kai-fa/data
    //    作用: 存放数据文件、数据集、日志、测试数据等与代码分离的持久化内容。
    //         可手动编辑此路径以匹配你的实际目录结构。
    "source=${localEnv:HOME}/kai-fa/data,target=/workspaces/data,type=bind,consistency=cached",

    // ③ SSH 密钥目录 → /home/vscode/.ssh（只读）
    //    macOS:       /Users/<用户名>/.ssh
    //    Linux:       /home/<用户名>/.ssh
    //    Windows:     /c/Users/<用户名>/.ssh
    //    作用: 容器内 Git 操作 (push/pull) 直接使用宿主机 SSH 密钥认证,
    //         无需在容器内重新生成或配置。
    //    只读原因: 防止容器内误操作 (如 rm -rf) 删除宿主机密钥。
    "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,consistency=cached,readonly",

    // ④ Git 全局配置 → /home/vscode/.gitconfig（只读）
    //    macOS:       /Users/<用户名>/.gitconfig
    //    Linux:       /home/<用户名>/.gitconfig
    //    Windows:     /c/Users/<用户名>/.gitconfig
    //    作用: 继承宿主机的 Git user.name / user.email / 别名等配置,
    //         避免每次重建容器后重新设置。
    //    只读原因: 防止容器内操作覆盖宿主机配置。
    //    注意: 若宿主机无此文件,启动时会输出警告但不影响使用。
    "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,consistency=cached,readonly"
  ],

  // ============================================================
  // Features — 微软维护的即插即用功能模块
  // 文档: https://containers.dev/features
  // ============================================================
  "features": {

    // Docker-out-of-Docker: 将宿主机的 docker socket 挂载到容器内
    //   容器内执行 docker 命令时实际操作宿主机的 Docker daemon,
    //   共享镜像缓存,性能优于 Docker-in-Docker,无需特权模式。
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},

    // Node.js: 使用 LTS 版本,附带 pnpm 包管理器
    //   覆盖 universal 镜像自带的 Node.js 版本以确保为最新 LTS。
    "ghcr.io/devcontainers/features/node:1": {
      "version": "lts",
      "pnpm": true
    },

    // Git: 自动从宿主机继承 user.name / user.email 配置
    "ghcr.io/devcontainers/features/git:1": {},

    // Common Utilities: Zsh / curl / git / less 等常用工具
    //   configureZshAsDefaultShell 确保容器内默认 Shell 为 Zsh。
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true,
      "configureZshAsDefaultShell": true,
      "username": "vscode",
      "uid": "1000"
    }
  },

  // ============================================================
  // VS Code 自定义设置
  // ============================================================
  "customizations": {
    "vscode": {

      // 编辑器设置
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh",
        "editor.formatOnSave": true,
        "files.autoSave": "onFocusChange"
      },

      // 自动安装的扩展
      "extensions": [
        "dbaeumer.vscode-eslint",          // ESLint
        "esbenp.prettier-vscode",           // Prettier
        "ms-python.python",                 // Python
        "golang.go",                        // Go
        "rust-lang.rust-analyzer"           // Rust
      ]
    }
  },

  // ============================================================
  // 容器环境变量
  // ============================================================
  "containerEnv": {
    // Docker-out-of-Docker 所需:
    // 告诉容器内的 Docker CLI 通过 socket 与宿主机 Docker daemon 通信
    "DOCKER_HOST": "unix:///var/run/docker.sock"
  },

  // ============================================================
  // docker run 附加参数
  // ============================================================
  "runArgs": [
    // 使用宿主机网络栈,简化网络访问,避免端口映射
    "--network=host"
  ],

  // ============================================================
  // 容器创建完成后执行
  // ============================================================
  "postCreateCommand": "echo 'Dev container ready.' && zsh"
}
```

- [ ] **Step 2: 验证 JSON 格式有效**

```bash
python3 -c "import json; json.load(open('.devcontainer/devcontainer.json'))" 2>&1
```

> 注：devcontainer.json 是 JSONC（含注释），标准 `json.load` 会报错。实际目的是确保括号/引号配对正确。若报 JSON 解析错但提示是关于 `//` 或注释符的，则为正常（JSONC 合法）。

---

### Task 3: 创建 build.sh

**Files:**
- Create: `scripts/build.sh`

- [ ] **Step 1: 创建目录并写入 build.sh**

```bash
mkdir -p scripts
```

```bash
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
```

- [ ] **Step 2: 添加可执行权限**

```bash
chmod +x scripts/build.sh
```

---

### Task 4: 创建 start.sh

**Files:**
- Create: `scripts/start.sh`

- [ ] **Step 1: 写入 start.sh**

```bash
#!/usr/bin/env bash
# ============================================================
# start.sh — 按名启动开发容器
#
# 用法:
#   ./scripts/start.sh <容器名> <宿主机路径>           首次启动,或进入已有容器
#   ./scripts/start.sh <容器名> <宿主机路径> -f       强制删除旧容器并新建
#
# 示例:
#   ./scripts/start.sh my-project ~/kai-fa/projects/foo
#   ./scripts/start.sh my-project ~/kai-fa/projects/foo -f
#   ./scripts/start.sh playground ~/Desktop/experiment
#
# 行为:
#   ┌─ 检查镜像 safe-agent-dev:latest 是否存在
#   │   └─ 不存在 → 自动调用 scripts/build.sh 构建
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
    echo "  $0 <容器名> <宿主机路径>           启动/进入容器"
    echo "  $0 <容器名> <宿主机路径> -f        强制重建容器"
    echo ""
    echo "示例:"
    echo "  $0 my-project ~/kai-fa/projects/foo"
    echo "  $0 my-project ~/kai-fa/projects/foo -f"
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

if [ $# -ge 3 ] && [ "$3" = "-f" ]; then
    FORCE_RECREATE=true
fi

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
    "${SCRIPT_DIR}/build.sh"
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
```

- [ ] **Step 2: 添加可执行权限**

```bash
chmod +x scripts/start.sh
```

---

### Task 5: 创建 README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: 写入 README.md**

```markdown
# Safe Agent Dev Container

基于微软 [Dev Containers Universal](https://github.com/devcontainers/images) 镜像构建的自定义开发容器环境。

## 前置要求

| 依赖 | 最低版本 | 检查命令 |
|------|---------|----------|
| Docker | 20.10+ | `docker --version` |
| VS Code | 1.85+ | `code --version` |
| VS Code Dev Containers 扩展 | 最新 | 扩展商店搜索安装 |

启动前请确保宿主机以下目录存在:

```bash
mkdir -p ~/kai-fa/projects ~/kai-fa/data
```

> 若目录不存在，容器启动时会明确报错并提示缺失路径。

## 快速开始

### 方式一: VS Code Dev Containers

1. 在 VS Code 中打开本项目
2. 按 `Cmd+Shift+P`（macOS）或 `Ctrl+Shift+P`（Windows/Linux）
3. 选择 **"Dev Containers: Reopen in Container"**
4. 等待镜像构建完成（首次约 5-10 分钟，后续秒级进入）

### 方式二: 宿主机脚本

```bash
# 构建镜像
./scripts/build.sh

# 启动容器
./scripts/start.sh my-project ~/kai-fa/projects/my-app
```

## 多容器并行

同一镜像可启动任意多个独立容器：

```bash
# 同时运行多个独立容器
./scripts/start.sh project-a ~/kai-fa/projects/foo
./scripts/start.sh project-b ~/kai-fa/projects/bar
./scripts/start.sh playground ~/Desktop/experiment

# 两个容器挂载同一路径 (各自独立,互不影响)
./scripts/start.sh session-1 ~/kai-fa/projects/shared
./scripts/start.sh session-2 ~/kai-fa/projects/shared

# 强制重建容器 (镜像更新后或环境被搞脏时)
./scripts/start.sh project-a ~/kai-fa/projects/foo -f
```

## 容器内路径结构

启动 `start.sh project-a ~/Desktop/foo` 后,容器内可见:

```
/workspaces/
├── foo/                  ← 专属工作区 (来自 start.sh 参数)
├── projects/             ← 全局共享目录 (来自 ~/kai-fa/projects)
└── data/                 ← 全局共享目录 (来自 ~/kai-fa/data)

/home/vscode/
├── .ssh/                 ← 只读,继承宿主机 SSH 密钥
└── .gitconfig            ← 只读,继承宿主机 Git 配置
```

## 自定义路径

### 修改固定挂载

编辑 `.devcontainer/devcontainer.json` 的 `"mounts"` 数组,修改 `source` 字段为目标路径。注释中已标注各路径的跨平台解析方式和作用。

### 修改容器内挂载名

编辑 `scripts/start.sh` 中 `MOUNT_BASENAME` 相关逻辑。

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| 启动报 "no such file or directory" | 宿主机挂载路径不存在 | `mkdir -p ~/kai-fa/projects ~/kai-fa/data` |
| 提示 "Cannot connect to Docker daemon" | Docker socket 未正确挂载 | 确认 `/var/run/docker.sock` 存在; 重启 Docker Desktop |
| VS Code 插件未自动安装 | 网络问题导致 Feature 安装失败 | `Cmd+Shift+P` → "Developer: Reload Window" 触发重装 |
| 容器内 `docker` 命令报权限错 | socket 权限不足 | 确认宿主机用户属于 `docker` 组 |
| macOS 上容器网络不通 | Docker Desktop 网络限制 | `--network=host` 在 macOS 下表现为 localhost 互通 |

## 文件结构与职责

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | 基于 `mcr.microsoft.com/devcontainers/universal:latest`，补充 ripgrep/fd/bat 等 CLI 工具，安装 pnpm，配置 Zsh |
| `.devcontainer/devcontainer.json` | 容器配置 | 声明固定挂载（`kai-fa/projects`、`kai-fa/data`、`.ssh`、`.gitconfig`），配置微软 Features（Docker-out-of-Docker、Node LTS + pnpm、Git），VS Code 插件和设置，`--network=host` |
| `scripts/build.sh` | 宿主机脚本 | 调用 `docker build` 构建 `safe-agent-dev:latest` 镜像，供 VS Code 和 `start.sh` 共用 |
| `scripts/start.sh` | 宿主机脚本 | 按容器名管理生命周期：创建新容器（含固定挂载 + 专属工作区）、复用已有容器、强制重建（`-f`）、进入容器 Shell |
| `README.md` | 文档 | 前置要求、快速开始、多容器使用、路径自定义、故障排除 |
```

- [ ] **Step 2: 验证最终文件结构**

```bash
find . -type f | sort
```

期望输出:
```
./.devcontainer/Dockerfile
./.devcontainer/devcontainer.json
./README.md
./scripts/build.sh
./scripts/start.sh
```
