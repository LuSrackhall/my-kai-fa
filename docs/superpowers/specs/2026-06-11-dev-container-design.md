# Dev Container 开发环境设计规格书

| 属性 | 值 |
|------|-----|
| 日期 | 2026-06-11 |
| 状态 | 已确认 |
| 版本 | 2.0 |
| 基础镜像 | `mcr.microsoft.com/devcontainers/base:ubuntu` (multi-arch) |

---

## 1. 目标与范围

### 1.1 目标

构建一个基于微软 Dev Containers 通用镜像的自定义开发容器，满足以下需求：

- **通用开发环境** — 支持 Node.js / TypeScript / Python / Go / Rust 等多语言开发
- **固定路径挂载** — 宿主机预设的开发目录（`kai-fa/projects`、`kai-fa/data`）始终在容器中可见
- **宿主机配置继承** — `.ssh` 密钥和 `.gitconfig` 自动挂载到容器，无需重复配置
- **Docker-out-of-Docker** — 容器内可使用宿主机 Docker，共享镜像和缓存
- **多容器并行** — 支持从同一镜像启动任意多个独立容器，每个容器可挂载不同（或相同）的宿主机路径
- **安全隔离** — 容器不获取特权模式，不做权限升级，不暴露不必要的宿主机路径

### 1.2 范围

| 范围内 | 范围外 |
|--------|--------|
| Dockerfile + devcontainer.json 配置 | Kubernetes / 集群部署 |
| 宿主机 shell 脚本（构建、启动） | CI/CD 管道集成 |
| VS Code Dev Containers 集成 | IDE 之外的远程开发方案 |
| 单宿主机多容器并行 | Windows 原生 Docker（仅保证 WSL2 兼容） |
| README 使用文档 | 图形化界面管理工具 |

---

## 2. 文件结构

```
safe-agent-test/                          ← 项目根目录
├── .devcontainer/
│   ├── devcontainer.json                 ← VS Code Dev Containers 核心配置
│   └── Dockerfile                        ← 基于 universal 的自定义镜像定义
├── scripts/
│   ├── build.sh                          ← 构建镜像脚本（宿主机执行）
│   └── start.sh                          ← 按名启动容器脚本（宿主机执行）
└── README.md                             ← 使用说明 + 文件结构职责表
```

**设计原则：** `.devcontainer/` 目录由 VS Code Dev Containers 扩展自动识别；`scripts/` 目录独立于 IDE，供终端直接调用。两份入口（IDE + CLI）共享同一个 Dockerfile，确保环境一致性。

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | 声明基础镜像、追加系统工具、运行时、Shell 配置 |
| `.devcontainer/devcontainer.json` | 容器配置 | 声明固定挂载、微软 Features、VS Code 设置与插件、运行时参数 |
| `scripts/build.sh` | 宿主机脚本 | 调用 `docker build` 构建 `safe-agent-dev:latest` 镜像 |
| `scripts/start.sh` | 宿主机脚本 | 按容器名管理生命周期：创建、复用、强制重建、进入容器 |
| `README.md` | 文档 | 前置要求、快速开始、多容器使用、路径自定义、故障排除 |

---

## 3. Dockerfile 设计

### 3.1 文件位置

`.devcontainer/Dockerfile`

### 3.2 内容

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

### 3.3 设计决策

| 决策 | 理由 |
|------|------|
| 从 `universal:latest` 而非 `base:ubuntu` 构建 | 省去手动安装 Node/Python/Go/Rust 等运行时的配置工作，利用微软官方维护的多语言环境 |
| 保留 Java（universal 自带） | 仅占用约 300MB 磁盘，不影响其他语言使用，且未来可能用到 |
| 使用 `vscode` 用户 (UID 1000) | 与微软 devcontainer 约定一致，避免文件权限问题（容器内创建的文件在宿主机上属主正确） |
| 全局安装 pnpm | `universal` 自带 Node + npm，pnpm 是增量工具，放在镜像层避免每个项目重复安装 |
| 不在 Dockerfile 中配置 Docker-out-of-Docker | Docker-out-of-Docker 通过 devcontainer.json 的 Features 机制挂载宿主机 socket，不写入镜像，避免镜像携带 socket |
| 不在容器内做文件存在性检查或兜底创建 | 遵循"显式失败"原则：路径不存则启动报错，错误信息由 Docker 直接给出，用户根据 README 创建所需目录 |

---

## 4. devcontainer.json 设计

### 4.1 文件位置

`.devcontainer/devcontainer.json`

### 4.2 内容

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

### 4.3 设计决策

| 决策 | 理由 |
|------|------|
| `build.context: ".."` | 构建上下文为项目根目录，Dockerfile 可引用项目根的文件（如 `.dockerignore`） |
| `${localEnv:HOME}` 变量 | 动态解析宿主机 Home，跨用户跨平台通用，比硬编码路径更健壮 |
| `consistency:cached` | macOS 上显著提升 bind mount 性能，Linux/Windows 上无负面影响 |
| `.ssh` 和 `.gitconfig` 只读挂载 | 安全性措施，防止容器内误操作（如脚本失控）修改或删除宿主机敏感文件 |
| `ghcr.io/devcontainers/features/git:1` | 虽然 universal 已含 Git，但此 Feature 会自动从宿主机同步 user.name/user.email，减少手动配置 |
| `containerEnv.DOCKER_HOST` | Docker-out-of-Docker Feature 的必需配置，缺失会导致容器内 `docker` 命令报 "Cannot connect to Docker daemon" |
| `--network=host` | 容器与宿主机共享网络，避免每个端口都要在 `forwardPorts` 中声明；仅在 macOS Docker Desktop 下表现为 localhost 共享 |
| 不在 `mounts` 中做路径兜底 | 路径不存在时 Docker 直接报错，错误信息清晰，用户根据 README 创建目录 |

---

## 5. build.sh 设计

### 5.1 文件位置

`scripts/build.sh`

### 5.2 内容

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

### 5.3 设计决策

| 决策 | 理由 |
|------|------|
| 固定 tag `safe-agent-dev:latest` | 简化引用与管理，不需要版本号追踪；如需回滚可通过 `docker image ls` 查看历史层 |
| `set -euo pipefail` | 脚本任何一步失败立即退出，未定义变量报错，管道任一命令失败即视为整体失败 |
| `--file .devcontainer/Dockerfile` | 显式指定 Dockerfile 路径，不依赖当前目录 |
| 从项目根目录执行 | 构建上下文包含 `.dockerignore`（后续可配置），构建上下文 `.(项目根)` |

---

## 6. start.sh 设计

### 6.1 文件位置

`scripts/start.sh`

### 6.2 内容

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
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

### 6.3 流程详解

```
start.sh <容器名> <路径> [-f]
│
├─ [1] 镜像检查
│   └─ docker image inspect safe-agent-dev:latest
│       ├─ 存在 → 继续
│       └─ 不存在 → 自动调用 scripts/build.sh
│
├─ [2] -f 参数处理
│   └─ docker ps -a 检查同名容器
│       ├─ 存在 → docker rm -f <容器名>
│       └─ 不存在 → 跳过
│
├─ [3] 容器存在性检查
│   └─ docker ps -a --filter name=<容器名>
│       │
│       ├─ 存在 + 运行中 → docker exec -it <容器名> zsh → 退出脚本
│       ├─ 存在 + 已停止 → docker start <容器名> → docker exec -it <容器名> zsh → 退出脚本
│       │
│       └─ 不存在 → 继续到 [4]
│
├─ [4] 宿主机目录校验
│   └─ 检查 ~/kai-fa/projects、~/kai-fa/data、~/.ssh 是否存在
│       ├─ 全部存在 → 继续
│       └─ 有缺失 → 报错列出缺失目录, 建议 mkdir -p, 退出脚本
│
└─ [5] 创建新容器
    └─ docker run -it \
        --name <容器名> \
        --hostname <容器名> \
        --network=host \
        -v <指定路径>:/workspaces/<basename> \
        -v ~/kai-fa/projects:/workspaces/projects \
        -v ~/kai-fa/data:/workspaces/data \
        -v ~/.ssh:/home/vscode/.ssh:ro \
        -v ~/.gitconfig:/home/vscode/.gitconfig:ro \
        -v /var/run/docker.sock:/var/run/docker.sock \
        safe-agent-dev:latest zsh
```

### 6.4 容器内可见的路径结构

启动 `start.sh project-a ~/Desktop/foo` 后，容器内可见：

```
/workspaces/
├── foo/                  ← 专属工作区（来自 start.sh 参数）
├── projects/             ← 全局共享目录（来自固定挂载 ~/kai-fa/projects）
└── data/                 ← 全局共享目录（来自固定挂载 ~/kai-fa/data）

/home/vscode/
├── .ssh/                 ← 只读，继承宿主机 SSH 密钥
└── .gitconfig            ← 只读，继承宿主机 Git 配置
```

### 6.5 设计决策

| 决策 | 理由 |
|------|------|
| 同名容器复用而非每次新建 | 容器内安装的工具、未保存的终端状态不会丢失，使用完 `exit` 后下次直接进入 |
| `-f` 强制重建 | 提供明确的"重置"入口，适用于镜像更新后需重新创建容器、或容器环境被搞脏的场景 |
| 启动前校验宿主机目录存在性 | 明确失败原因，给清晰的修复建议 (`mkdir -p`)，避免 Docker 模糊的错误信息 |
| 绝对路径解析 (`cd + pwd`) | 避免相对路径导致的挂载不一致问题 |
| `basename` 确定容器内挂载名 | 简单直观，`~/Desktop/foo` → `/workspaces/foo`，不引入额外参数 |
| `--hostname` 设为容器名 | 终端的 hostname 提示符可区分当前在哪个容器中 |
| devcontainer.json 和 start.sh 挂载策略一致 | 固定挂载目录、Docker socket、网络模式完全一致，避免同一镜像在不同入口下行为不同 |
| Docker-out-of-Docker socket 直接挂载而非通过 Feature | `start.sh` 无法使用微软 Features 机制，因此在脚本中直接 `-v /var/run/docker.sock` |

---

## 7. README.md 设计

### 7.1 文件位置

`README.md`（项目根目录）

### 7.2 内容大纲

```markdown
# Safe Agent Dev Container

基于微软 [Dev Containers Universal](https://github.com/devcontainers/images)
镜像构建的自定义开发容器环境。

## 前置要求

| 依赖 | 最低版本 | 检查命令 |
|------|---------|----------|
| Docker | 20.10+ | `docker --version` |
| VS Code | 1.85+ | `code --version` |
| VS Code Dev Containers 扩展 | 最新 | 扩展商店搜索安装 |

启动前请确保宿主机以下目录存在:

mkdir -p ~/kai-fa/projects ~/kai-fa/data

## 快速开始

### 方式一: VS Code Dev Containers

1. 在 VS Code 中打开本项目
2. Cmd+Shift+P → "Dev Containers: Reopen in Container"
3. 等待构建完成

### 方式二: 宿主机脚本

./scripts/build.sh
./scripts/start.sh my-project ~/kai-fa/projects/my-app

## 多容器并行

# 同时运行多个独立容器
./scripts/start.sh project-a ~/kai-fa/projects/foo
./scripts/start.sh project-b ~/kai-fa/projects/bar
./scripts/start.sh playground ~/Desktop/experiment

# 两个容器挂载同一路径 (各自独立)
./scripts/start.sh session-1 ~/kai-fa/projects/shared
./scripts/start.sh session-2 ~/kai-fa/projects/shared

# 强制重建 (镜像更新后)
./scripts/start.sh project-a ~/kai-fa/projects/foo -f

## 自定义路径

编辑 .devcontainer/devcontainer.json 的 "mounts" 数组，
修改 source 字段为目标路径。

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| 启动报 "no such file" | 宿主机挂载路径不存在 | `mkdir -p ~/kai-fa/projects ~/kai-fa/data` |
| 提示 "Cannot connect to Docker" | Docker socket 未挂载 | 确认 `/var/run/docker.sock` 存在 |
| VS Code 插件未自动安装 | 网络问题 | `Cmd+Shift+P` → "Developer: Reload Window" |

## 文件结构与职责

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | 声明基础镜像、追加系统工具、运行时、Shell 配置 |
| `.devcontainer/devcontainer.json` | 容器配置 | 声明固定挂载、微软 Features、VS Code 设置与插件、运行时参数 |
| `scripts/build.sh` | 宿主机脚本 | 调用 `docker build` 构建 `safe-agent-dev:latest` 镜像 |
| `scripts/start.sh` | 宿主机脚本 | 按容器名管理生命周期：创建、复用、强制重建、进入容器 |
| `README.md` | 文档 | 前置要求、快速开始、多容器使用、路径自定义、故障排除 |
```

---

## 8. 使用工作流

### 8.1 首次设置

```bash
# 1. 创建必需的宿主机目录
mkdir -p ~/kai-fa/projects ~/kai-fa/data

# 2. 构建镜像
cd /path/to/safe-agent-test
./scripts/build.sh

# 3. 启动第一个容器
./scripts/start.sh my-dev ~/kai-fa/projects
```

### 8.2 日常使用

| 场景 | 操作 |
|------|------|
| VS Code 开发 | `Cmd+Shift+P` → "Reopen in Container" |
| 终端快速开发 | `./scripts/start.sh <name> <path>` |
| 回到已有容器 | `./scripts/start.sh <name> <path>`（同名自动进入） |
| 重置容器 | `./scripts/start.sh <name> <path> -f` |
| Dockerfile 变更后 | `./scripts/build.sh` 然后 `-f` 重建容器 |

### 8.3 多容器场景

```bash
# 三个项目同时开发,各自独立容器
./scripts/start.sh foo-dev ~/kai-fa/projects/foo
./scripts/start.sh bar-dev ~/kai-fa/projects/bar
./scripts/start.sh playground ~/Desktop/sandbox
```

每个容器：
- 有独立的工作区挂载（`/workspaces/<basename>`）
- 共享 `~/kai-fa/projects` 和 `~/kai-fa/data`
- 可用宿主机 Docker（通过 socket）
- `exit` 退出后容器保持，下次同名进入恢复状态

---

## 9. 安全考量

| 项目 | 措施 |
|------|------|
| SSH 密钥 | 只读挂载（`readonly`），容器内无法修改或删除宿主机密钥文件 |
| Git 配置 | 只读挂载，容器内配置修改不影响宿主机 |
| Docker-out-of-Docker | 仅挂载 socket 文件，不授予特权模式（无 `--privileged`） |
| 网络 | `--network=host` 共享宿主机网络，容器服务可直接被宿主机 localhost 访问 |
| 路径不存在 | 显式失败，列出缺失路径和修复命令，不静默降级 |
| 容器隔离 | 每个容器独立文件系统、进程空间、网络命名空间（`--network=host` 除外） |

---

## 10. 开放问题与未来扩展

| 项目 | 状态 | 说明 |
|------|------|------|
| Windows 原生 Docker 支持 | 暂不支持 | 仅在 WSL2 下验证兼容性 |
| `.dockerignore` 配置 | 待后续 | 防止 `node_modules` 等进入构建上下文 |
| 镜像版本管理 | 固定 `latest` | 后续可按需引入 semver tag |
| 多架构构建 | 暂不支持 | 当前仅 linux/amd64, M 系列 Mac 通过 Rosetta 运行 |
