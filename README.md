# Safe Agent Dev Container

基于微软 [Dev Containers Base Ubuntu](https://github.com/devcontainers/images) 镜像构建的自定义开发容器环境。

## 语言运行时

版本管理器预装在镜像层中，容器启动即用，运行时自由切换版本：

| 运行时 | 版本管理器 | 默认版本 | 切版本 |
|--------|-----------|---------|--------|
| Node.js | nvm | LTS (构建时最新) | `nvm use 22` |
| Python | 系统 python3 + pip + venv | Ubuntu 自带 | 通过 venv 隔离项目 |
| Go | 官方二进制 `/usr/local/go` | 1.23.4 | 改 Dockerfile 中 GO_VERSION 重建镜像 |
| Rust | rustup | stable | `rustup default nightly` |

各管理器常用命令见 [docs/version-managers.md](docs/version-managers.md)。

## 架构支持

基础镜像 `mcr.microsoft.com/devcontainers/base:ubuntu` 是 multi-arch 镜像，同时支持 `linux/amd64` 和 `linux/arm64`。

| 宿主机 | 默认架构 | 性能 |
|--------|---------|------|
| Apple Silicon Mac (M1/M2/M3) | `linux/arm64` | 原生 ARM64 |
| Intel Mac | `linux/amd64` | 原生 AMD64 |
| Linux (x86-64) | `linux/amd64` | 原生 AMD64 |
| Windows (WSL2) | `linux/amd64` | 原生 AMD64 |

```bash
# 默认: 自动选择原生架构
./scripts/build.sh

# 跨架构 (M 系列 Mac 上构建 Rosetta 模拟的 amd64 版本)
./scripts/build.sh --platform linux/amd64
```

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
4. 等待镜像构建完成（首次约 3-5 分钟，后续秒级进入）

### 方式二: 宿主机脚本

```bash
# 构建镜像
./scripts/build.sh

# 启动容器
./scripts/start.sh my-project ~/kai-fa/projects/my-app
```

### 方式三: VS Code 连接到脚本启动的容器

如果你已经用 `start.sh` 启动了容器,想让 VS Code 连上去:

1. 打开 VS Code
2. 按 `Cmd+Shift+P` → 选择 **"Dev Containers: Attach to Running Container"**
3. 在列表中选择你的容器名 (如 `my-project`)
4. VS Code 几秒后连入,左下角显示容器名

> **注意:** `Reopen in Container` 和 `Attach to Running Container` 是两条不同路径。
> - `Reopen in Container` — VS Code 自己根据 `devcontainer.json` 构建并启动新容器
> - `Attach to Running Container` — 连接到一个已经运行的容器 (脚本启动的)
>
> 两者的区别: `Reopen` 时会执行 `devcontainer.json` 中的 Features 和 `postCreateCommand`，而 `Attach` 不会。

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

# 强制重建 + 指定 amd64 架构 (M 系列 Mac 上 Rosetta 模拟)
./scripts/start.sh project-a ~/kai-fa/projects/foo -f --platform linux/amd64
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
| Apple Silicon 上拉取报 "no match for platform" | 某些镜像没有 ARM64 版本 | 使用 `--platform linux/amd64` 通过 Rosetta 2 运行 |
| 容器内 `node`/`cargo` 等命令找不到 | init-env.sh 未 source | 手动执行 `source /usr/local/bin/init-env.sh` |

## 文件结构与职责

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | 基于 `base:ubuntu` (multi-arch)，安装 CLI 工具 + 版本管理器 (nvm / python3 / Go / rustup)，COPY init-env.sh，配置 Zsh。不包含 Java/.NET/PHP/Ruby |
| `.devcontainer/init-env.sh` | Shell 初始化 | 统一激活所有版本管理器（nvm / Go PATH / rustup），被 .zshrc、.bashrc、postCreateCommand 三处 source |
| `.devcontainer/devcontainer.json` | 容器配置 | 固定挂载 + 容器级 Features（Docker-out-of-Docker、Git、common-utils）+ VS Code 设置 |
| `scripts/build.sh` | 宿主机脚本 | 构建 `safe-agent-dev:latest`，默认自动检测架构，支持 `--platform` |
| `scripts/start.sh` | 宿主机脚本 | 容器生命周期管理（创建/复用/强制重建/进入），`-f` + `--platform` 透传 |
| `README.md` | 文档 | 前置要求、架构说明、快速开始、多容器使用、故障排除 |
| `docs/version-managers.md` | 参考 | nvm / pip / go / rustup 常用命令速查 |
