# Safe Agent Dev Container (`dsh-safe` 分支)

基于微软 [Dev Containers Base Ubuntu](https://github.com/devcontainers/images) 镜像构建的**隔离 AI Agent 开发容器**，为在真实 Linux 环境中运行 [DSH (DeepSeek Harness)](https://www.npmjs.com/package/@deepseek-ai/dsh) 而定制。

> **本分支相对 `main` 的定制**（安全模型全面收紧）:
>
> | 项 | main | dsh-safe |
> |----|------|----------|
> | docker.sock (宿主 Docker 总开关) | 挂载进容器 | ❌ 移除 |
> | `~/.ssh` / `~/.gitconfig` | 只读挂载进容器（只读防删不防读） | ❌ 移除，Git 身份改为持久化在交互区 |
> | 网络 | `--network=host`（本机服务对容器可见） | ❌ 独立网络，GUI 走 `宿主13080 → 容器3081(socat) → 容器回环3080` |
> | 挂载模型 | projects + data 双固定挂载 + 每次指定路径 | ✅ 唯一挂载：长久交互区 `DSH_SAFE_DIR` 整块挂载 |
> | DSH 支持 | 无 | ✅ `dsh-setup` 一键安装/更新（固化命令不锁版本） |

## 安全模型

容器可见的**唯一**宿主机目录是长久交互区 `DSH_SAFE_DIR`；此外：

- 无 docker.sock —— 容器内 agent 无法借宿主 Docker 越过挂载边界
- 无 `.ssh` / `.gitconfig` 挂载 —— 宿主密钥与配置不被读取外带
- 无 `--privileged`、无 host 网络 —— GUI 入口仅 `127.0.0.1:13080` 一扇门（经容器内 socat 中继到 dsh 的回环 3080）
- **出站网络开放（知情取舍，2026-08 决策）**：容器可自由访问互联网(dsh 调 API/装包的前提)与局域网；OrbStack 特性下宿主上仅绑回环的服务(如主机版 dsh 的 3080)也经 `host.docker.internal` 对容器可见。已评估接受：文件挂载边界才是主防线，出站管控的维护成本与收益不成比例

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

基础镜像 multi-arch，Docker 自动选择原生架构：Apple Silicon → `linux/arm64`，Intel/PC → `linux/amd64`。跨架构用 `--platform` 参数。

## 前置要求

| 依赖 | 说明 |
|------|------|
| Docker Desktop **或** OrbStack | 已启动即可。OrbStack 天然可挂载任意 macOS 路径;Docker Desktop 需 File Sharing 包含交互区所在卷(默认名单已含 `/Volumes`) |
| 交互区目录 | 缺失时 `start.sh` 会自动创建;也可手动 `mkdir -p ~/dsh-safe` |
| VS Code (可选) | 仅 Dev Containers 入口需要 |

环境变量 `DSH_SAFE_DIR` 指定交互区位置，未设置时回退 `~/dsh-safe`。可写入 shell 配置持久化：

```bash
echo 'export DSH_SAFE_DIR=/Volumes/SSD980/dsh-safe' >> ~/.zshrc   # 本机示例
```

## 快速开始

### 方式一: start.sh CLI（推荐）

```bash
./scripts/build.sh          # 构建镜像 (首次约 3-5 分钟)
./scripts/start.sh main     # 启动并进入容器
```

进入容器后安装 dsh 并启动：

```zsh
dsh-setup                   # 安装最新版 dsh (以后更新也是这条命令)
dsh-web                     # 启动 DeepSeek Harness 的 Web UI
# (= 官方命令 dsh web --host 0.0.0.0 --no-open;
#  首次运行会引导完成配置)
# Mac 浏览器访问 http://127.0.0.1:13080 (容器那份;
# 主机自身的 dsh 仍在 http://127.0.0.1:3080,互不干扰)
```

### 方式二: VS Code Dev Containers

VS Code 打开本项目 → `Cmd+Shift+P` → **Dev Containers: Reopen in Container**。

### 方式三: Attach 到脚本启动的容器

`Cmd+Shift+P` → **Dev Containers: Attach to Running Container** → 选择容器名。
（注意: Reopen 会执行 Features/postCreate，Attach 不会。）

## 长久交互区与持久化

```
宿主机 $DSH_SAFE_DIR  ──bind mount──►  容器内 /workspaces/dsh-safe
├── 项目A/  项目B/  ...               ← 建子文件夹即新增项目,零操作
├── git/gitconfig                     ← Git 身份(见下),跨容器重建保留
└── (dsh 的配置/会话状态建议也放这里)   ← 容器 -f 重建后依然存在
```

Git 身份首次配置（容器内执行一次即可）：

```zsh
mkdir -p /workspaces/dsh-safe/git
git config --file /workspaces/dsh-safe/git/gitconfig user.name  "你的名字"
git config --file /workspaces/dsh-safe/git/gitconfig user.email "你的邮箱"
```

之后新 Shell 自动启用（由 `init-env.sh` 设置 `GIT_CONFIG_GLOBAL`）。

## 多容器并行

```bash
./scripts/start.sh session-1
./scripts/start.sh session-2        # 注意: 13080 门牌同一时刻只能归一个容器
./scripts/start.sh proj-a /Volumes/SSD980/dsh-safe/foo   # 额外把 foo 挂为本次主目录
./scripts/start.sh main -f          # 环境被搞脏时重置容器(dsh 重跑 dsh-setup 即恢复)
```

> 提示: 多个容器共享同一交互区时彼此可见区内全部项目——"容器间二次隔离"不属于本设计目标。

## 自定义

| 想改什么 | 改哪里 |
|----------|--------|
| 交互区路径 | 环境变量 `DSH_SAFE_DIR`（无需改文件） |
| GUI 端口 | `scripts/start.sh` 中 `DSH_GUI_HOST_PORT`(宿主侧)/`DSH_GUI_CONTAINER_PORT`,及 `.devcontainer/devcontainer.json` 中 `forwardPorts` |
| 额外固定挂载 | `.devcontainer/devcontainer.json` 的 `"mounts"` 数组 |

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| 报 "mount path not shared"(仅 Docker Desktop) | 未共享该卷 | Settings → Resources → File sharing 勾选对应路径;OrbStack 无此问题 |
| 浏览器打不开 127.0.0.1:13080 | dsh 未启动或宿主侧门牌被占 | 容器内先跑 `dsh`;确认 13080 无其他进程占用 |
| 容器内 `dsh` 找不到 | 新 Shell 未加载 PATH 或尚未安装 | `dsh-setup` 安装;或 `source /usr/local/bin/init-env.sh` |
| 容器内 `node`/`cargo` 找不到 | init-env.sh 未 source | 手动执行 `source /usr/local/bin/init-env.sh` |
| Apple Silicon 拉取报 platform 错 | 个别镜像无 ARM64 版本 | 加 `--platform linux/amd64` 走 Rosetta |
| VS Code 插件未自动安装 | 网络问题 | Reload Window 重试 |

## 文件结构与职责

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | base:ubuntu + CLI 工具 + 版本管理器 + COPY init-env/dsh-setup |
| `.devcontainer/init-env.sh` | Shell 初始化 | 版本管理器激活 + npm 用户级前缀 + 交互区 gitconfig 接线 |
| `.devcontainer/dsh-setup.sh` | DSH 引导 | 一条命令安装/更新 @deepseek-ai/dsh 到用户级 npm 前缀 |
| `.devcontainer/dsh-web.sh` | DSH 启动 | 固化官方 `dsh web` 的容器正确参数(--host 0.0.0.0 --no-open) |
| `.devcontainer/devcontainer.json` | 容器配置 | 交互区参数化挂载 + Features + forwardPorts(仅 3080) |
| `scripts/build.sh` | 宿主机脚本 | 构建 `safe-agent-dev:latest`,支持 `--platform` |
| `scripts/start.sh` | 宿主机脚本 | 容器生命周期: 创建/复用/强制重建/进入;安全运行参数在此落地 |
