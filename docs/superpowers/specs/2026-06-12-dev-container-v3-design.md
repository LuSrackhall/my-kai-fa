# Dev Container 开发环境设计规格书 v3.0

| 属性 | 值 |
|------|-----|
| 日期 | 2026-06-12 |
| 状态 | 已确认 |
| 版本 | 3.0 |
| 基础镜像 | `mcr.microsoft.com/devcontainers/base:ubuntu` (multi-arch) |

---

## 1. 目标与范围

### 1.1 目标

构建一个基于微软 Dev Containers 的自定义开发容器，满足以下需求：

- **通用开发环境** — 支持 Node.js / TypeScript / Python / Go / Rust 多语言开发，采用版本管理器（nvm/rustup/系统go）运行时自由切换版本
- **两条路径完全等价** — `start.sh`（docker run）和 VS Code `Reopen in Container` 进入后环境一致，都有全部运行时
- **固定路径挂载** — `kai-fa/projects`、`kai-fa/data` 始终在容器中可见
- **宿主机配置继承** — `.ssh`、`.gitconfig` 自动只读挂载
- **Docker-out-of-Docker** — 容器内使用宿主机 Docker
- **多容器并行** — 同一镜像启动任意多个独立容器，`--platform` 可选
- **跨平台原生** — macOS (ARM64 + AMD64)、Linux、Windows (WSL2) 均原生运行
- **安全隔离** — 不授予特权模式，不暴露不必要的宿主机路径

### 1.2 范围

| 范围内 | 范围外 |
|--------|--------|
| Dockerfile + init-env.sh + devcontainer.json | Kubernetes / 集群部署 |
| 宿主机 shell 脚本（build、start） | CI/CD 管道集成 |
| VS Code Dev Containers 集成 + Attach 模式 | 图形化界面管理工具 |
| 单宿主机多容器并行 | Windows 原生 Docker（仅保证 WSL2 兼容） |
| README + 版本管理器使用说明 | 独立远程开发方案 |

### 1.3 与 v2.0 的关键差异

| 项目 | v2.0 | v3.0 |
|------|------|------|
| 运行时安装位置 | devcontainer.json Features | Dockerfile 镜像层 |
| start.sh 能否用运行时 | ❌ 空 Ubuntu | ✅ 全部运行时 |
| 版本管理 | Features 装指定版本 | 版本管理器，运行时自由切换 |
| 新增文件 | — | init-env.sh |
| devcontainer.json | 含 node/python/go/rust Features | 只含容器级 Features |

---

## 2. 文件结构

```
safe-agent-test/                          ← 项目根目录
├── .devcontainer/
│   ├── Dockerfile                        ← 镜像定义：base:ubuntu + CLI 工具 + 版本管理器
│   ├── devcontainer.json                 ← 容器配置：挂载 + 容器级 Features + VS Code
│   └── init-env.sh                       ← 统一 Shell 初始化（所有版本管理器在此激活）
├── scripts/
│   ├── build.sh                          ← 构建镜像（支持 --platform）
│   └── start.sh                          ← 按名启动容器（支持 -f + --platform）
├── README.md                             ← 完整使用说明
└── docs/
    └── version-managers.md               ← 各语言版本管理器常用命令速查
```

| 文件 | 分类 | 职责 |
|------|------|------|
| `.devcontainer/Dockerfile` | 镜像定义 | 基于 `base:ubuntu`(multi-arch)，安装 CLI 工具、nvm(Node)、pip(Python)、Go、rustup(Rust)，配置 vscode 用户 |
| `.devcontainer/init-env.sh` | Shell 初始化 | 统一的 PATH 和版本管理器激活脚本，被 `.zshrc` 和 `.bashrc` 自动 source |
| `.devcontainer/devcontainer.json` | 容器配置 | 固定挂载、Docker-out-of-Docker + Git + common-utils Features、VS Code 插件/settings、postCreate |
| `scripts/build.sh` | 宿主机脚本 | `docker build -t safe-agent-dev:latest`，默认自动检测架构，支持 `--platform` |
| `scripts/start.sh` | 宿主机脚本 | 容器生命周期管理：创建/复用/强制重建/进入，`-f` + `--platform` 透传 |
| `README.md` | 文档 | 前置要求、架构说明、快速开始、多容器使用、故障排除 |
| `docs/version-managers.md` | 参考 | nvm / pip / go / rustup 的常用命令速查 |

---

## 3. Dockerfile 设计

### 3.1 文件位置

`.devcontainer/Dockerfile`

### 3.2 内容

```dockerfile
# ============================================================
# 基于微软 Dev Containers Base Ubuntu (multi-arch)
# 文档: https://github.com/devcontainers/images
# 
# base:ubuntu 已包含: Ubuntu, Git, curl, wget, vim, jq, 
#   vscode 用户 (UID 1000), Oh My Zsh
#
# 架构: linux/amd64 + linux/arm64 双原生支持
# ============================================================
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ============================================================
# 系统工具
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep fd-find bat htop tmux \
    jq tree unzip zip less man-db \
    build-essential curl wget ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Node.js — nvm (版本管理器)
# 构建时预装一个 LTS 作为默认版本
# ============================================================
ENV NVM_DIR=/usr/local/share/nvm
RUN mkdir -p "$NVM_DIR" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts \
    && nvm use --lts \
    && nvm alias default lts/*
ENV NODE_PATH="$NVM_DIR/versions/node/$(nvm version)/lib/node_modules"

# ============================================================
# Python — 系统 python3 + pip + venv
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Go — 官方二进制 (TARGETARCH 自动匹配 ARM64/AMD64)
# ============================================================
ARG GO_VERSION=1.23.4
ARG TARGETARCH
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH:-amd64}.tar.gz" \
    | tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:$PATH"

# ============================================================
# Rust — rustup (版本管理器)
# ============================================================
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/vscode/.cargo/bin:$PATH"

# ============================================================
# Shell 初始化
# init-env.sh 统一管理所有版本管理器的激活
# ============================================================
COPY .devcontainer/init-env.sh /usr/local/bin/init-env.sh
RUN chmod +x /usr/local/bin/init-env.sh
RUN echo 'source /usr/local/bin/init-env.sh' >> /home/vscode/.zshrc \
    && echo 'source /usr/local/bin/init-env.sh' >> /home/vscode/.bashrc

# ============================================================
# Zsh 别名
# ============================================================
RUN echo 'alias ll="ls -alh"' >> /home/vscode/.zshrc \
    && echo 'alias fd="fdfind"' >> /home/vscode/.zshrc \
    && echo 'alias bat="batcat"' >> /home/vscode/.zshrc

USER vscode
WORKDIR /workspaces
```

### 3.3 关键设计决策

| 决策 | 理由 |
|------|------|
| 运行时写入 Dockerfile 而非 Features | 确保 `start.sh`（docker run）和 VS Code Reopen 两条路径环境完全一致 |
| 使用版本管理器（nvm/rustup）而非固定版本 | 运行时自由切换版本，无需重建镜像。universal 镜像的做法 |
| `TARGETARCH` 自动变量 | Docker build 自动设置为宿主架构，Go 安装包自动匹配 ARM64/AMD64 |
| `init-env.sh` 统一入口 | PATH 变更集中一处，Zsh/Bash 都 source，减少重复配置 |
| `nvm install --lts` 在构建时执行 | 容器启动即有可用 Node，不需手动 `nvm install` |
| 移除 Java/.NET/PHP/Ruby | 用户明确不需要，保持镜像精简 |

---

## 4. init-env.sh 设计

### 4.1 文件位置

`.devcontainer/init-env.sh`

### 4.2 内容

```bash
#!/usr/bin/env bash
# ============================================================
# init-env.sh — 统一的 Shell 环境初始化
# 
# 被 .zshrc 和 .bashrc 自动 source，确保所有版本管理器
# 在新 Shell 中正确激活。
#
# 同时被 devcontainer.json 的 postCreateCommand 调用，
# 确保 VS Code Reopen 路径也能激活运行时。
# ============================================================

# ---- nvm (Node.js 版本管理器) ----
export NVM_DIR="/usr/local/share/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ---- Go ----
export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

# ---- Rust (rustup + cargo) ----
[ -s "$HOME/.cargo/env" ] && \. "$HOME/.cargo/env"
```

### 4.3 设计决策

| 决策 | 理由 |
|------|------|
| 独立文件而非直接写 `.zshrc` | 一处修改全局生效；zshrc/bashrc/postCreate 三处 source 同一文件 |
| `$HOME/go/bin` 在 PATH | Go 的 `go install` 安装的二进制放这里，自动可用 |
| 幂等设计 | `[ -s ... ]` 检查文件存在才 source，重复执行安全 |

---

## 5. devcontainer.json 设计

### 5.1 文件位置

`.devcontainer/devcontainer.json`

### 5.2 内容

```jsonc
{
  "name": "Safe Agent Dev",

  "build": {
    "dockerfile": "Dockerfile",
    "context": ".."
  },

  // ============================================================
  // 固定挂载点 — ${localEnv:HOME} 跨平台解析:
  //   macOS:    /Users/<用户名>
  //   Linux:    /home/<用户名>
  //   Windows:  /c/Users/<用户名> (WSL2)
  //
  // 路径不存在 → Docker 直接报错拒绝启动。
  // 请先创建:  mkdir -p ~/kai-fa/projects ~/kai-fa/data
  // ============================================================
  "mounts": [
    "source=${localEnv:HOME}/kai-fa/projects,target=/workspaces/projects,type=bind,consistency=cached",
    "source=${localEnv:HOME}/kai-fa/data,target=/workspaces/data,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,consistency=cached,readonly",
    "source=${localEnv:HOME}/.gitconfig,target=/home/vscode/.gitconfig,type=bind,consistency=cached,readonly"
  ],

  // ============================================================
  // Features — 仅容器级功能，语言运行时已在 Dockerfile 中
  // ============================================================
  "features": {
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true,
      "configureZshAsDefaultShell": true,
      "username": "vscode",
      "uid": "1000"
    }
  },

  // ============================================================
  // VS Code 设置与扩展
  // ============================================================
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh",
        "editor.formatOnSave": true,
        "files.autoSave": "onFocusChange"
      },
      "extensions": [
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode",
        "ms-python.python",
        "golang.go",
        "rust-lang.rust-analyzer"
      ]
    }
  },

  "containerEnv": {
    "DOCKER_HOST": "unix:///var/run/docker.sock"
  },
  "runArgs": ["--network=host"],

  // 激活所有版本管理器
  "postCreateCommand": "source /usr/local/bin/init-env.sh && echo 'Dev container ready.' && zsh"
}
```

### 5.3 设计决策

| 决策 | 理由 |
|------|------|
| 移除 `node`/`python`/`go`/`rust` Features | 运行时已在 Dockerfile 层，Features 装会冲突/冗余 |
| 保留 `common-utils` | 提供 Zsh 配置、oh-my-zsh 等容器级功能，不影响运行时 |
| `postCreateCommand` source init-env | 确保 VS Code Reopen 路径的集成终端也能激活版本管理器 |

---

## 6. build.sh 设计

`scripts/build.sh` — 不变。支持 `--platform linux/amd64|linux/arm64`，默认自动检测架构。

```bash
./scripts/build.sh                              # 自动架构
./scripts/build.sh --platform linux/amd64       # 强制 AMD64
```

构建参数通过 `docker build --platform` 传递，Dockerfile 中的 `ARG TARGETARCH` 会自动设置为对应架构，Go 安装包自动匹配。

---

## 7. start.sh 设计

`scripts/start.sh` — 不变。支持 `-f`（强制重建）和 `--platform`（透传给 build.sh），任意顺序。

```bash
./scripts/start.sh my-project ~/path                     # 启动/复用
./scripts/start.sh my-project ~/path -f                  # 强制重建
./scripts/start.sh my-project ~/path -f --platform linux/amd64  # 强制重建+架构
```

---

## 8. README.md 设计

### 8.1 文件位置

`README.md`（项目根目录）

### 8.2 内容要点

- 语言运行时说明：版本管理器预装在镜像中
- 三条 VS Code 路径：Reopen / Attach / start.sh + Attach
- 多容器并行示例
- 故障排除（新增 `nvm` 未生效 → `source /usr/local/bin/init-env.sh`）
- 文件结构职责表（含 init-env.sh）
- 指向 `docs/version-managers.md` 的链接

---

## 9. 版本管理器速查文档

### 9.1 文件位置

`docs/version-managers.md`

### 9.2 内容

```markdown
# 版本管理器常用命令速查

本容器预装了以下版本管理器，可在运行时自由切换版本。

## Node.js — nvm

| 操作 | 命令 |
|------|------|
| 查看已安装版本 | `nvm ls` |
| 查看可用 LTS 版本 | `nvm ls-remote --lts` |
| 安装指定版本 | `nvm install 22` |
| 切换版本 | `nvm use 22` |
| 设置默认版本 | `nvm alias default 22` |
| 查看当前版本 | `node -v` |

## Python

| 操作 | 命令 |
|------|------|
| 查看版本 | `python3 --version` |
| 创建虚拟环境 | `python3 -m venv .venv` |
| 激活虚拟环境 | `source .venv/bin/activate` |
| 安装包 | `pip install <package>` |

## Go

| 操作 | 命令 |
|------|------|
| 查看版本 | `go version` |
| 构建 | `go build ./...` |
| 运行 | `go run main.go` |
| 安装工具 | `go install <package>@latest` |

> Go 通过 `/usr/local/go` 安装。切换版本需改 Dockerfile 中 `GO_VERSION` 并重建镜像。

## Rust — rustup

| 操作 | 命令 |
|------|------|
| 查看已安装工具链 | `rustup show` |
| 安装工具链 | `rustup install stable` / `rustup install nightly` |
| 切换默认工具链 | `rustup default stable` / `rustup default nightly` |
| 更新 rustup | `rustup update` |
| 查看版本 | `rustc --version` / `cargo --version` |
| 添加组件 | `rustup component add clippy rustfmt` |

## Shell 环境

所有版本管理器通过 `~/.zshrc` 自动激活。
如果环境中某个命令找不到，手动执行：

source /usr/local/bin/init-env.sh
```

---

## 10. 两条路径等价性验证

| 命令 | start.sh 启动 | VS Code Reopen | Attach |
|------|:---:|:---:|:---:|
| `node -v` | ✅ | ✅ | ✅ |
| `npm -v` | ✅ | ✅ | ✅ |
| `nvm use 22` | ✅ | ✅ | ✅ |
| `python3 --version` | ✅ | ✅ | ✅ |
| `go version` | ✅ | ✅ | ✅ |
| `rustc --version` | ✅ | ✅ | ✅ |
| `cargo --version` | ✅ | ✅ | ✅ |
| `docker ps` (宿主) | ✅ | ✅ | ✅ |
| `git push` | ✅ | ✅ | ✅ |

---

## 11. 安全考量

| 项目 | 措施 |
|------|------|
| SSH 密钥 | 只读挂载 |
| Git 配置 | 只读挂载 |
| Docker-out-of-Docker | 仅挂载 socket，无 `--privileged` |
| 网络 | `--network=host`，macOS 下 localhost 互通 |
| 路径不存在 | 显式失败，列出缺失路径和修复命令 |
