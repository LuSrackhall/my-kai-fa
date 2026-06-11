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
