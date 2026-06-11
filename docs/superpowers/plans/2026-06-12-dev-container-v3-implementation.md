# Dev Container v3.0 — 运行时从 Features 移至 Dockerfile 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Node/Python/Go/Rust 运行时从 devcontainer.json Features 移至 Dockerfile 镜像层（使用版本管理器 nvm/rustup），新增 init-env.sh 统一 Shell 初始化，确保 `start.sh` 和 VS Code Reopen 两条路径环境完全一致。

**Architecture:** Dockerfile 作为运行时唯一安装源，init-env.sh 作为 PATH 和版本管理器激活的统一入口。devcontainer.json 精简为纯容器级配置。build.sh 和 start.sh 不变。

**Tech Stack:** Docker, Bash, nvm, rustup, Go binary

---

### Task 1: 重写 Dockerfile — 系统工具层

**Files:**
- Modify: `.devcontainer/Dockerfile` (全量重写)

本次变更是把运行时装进镜像层，改动集中且不可拆分。为避免中间状态不可用，将完整 Dockerfile 一次性写入。

- [ ] **Step 1: 写入新的 Dockerfile（完整内容）**

```dockerfile
# ============================================================
# 基于微软 Dev Containers Base Ubuntu (multi-arch)
# 文档: https://github.com/devcontainers/images
# 
# base:ubuntu 已包含: Ubuntu, Git, curl, wget, vim, jq,
#   vscode 用户 (UID 1000), Oh My Zsh
#
# 架构: linux/amd64 + linux/arm64 双原生支持
#   Docker 自动选择与宿主机匹配的架构。
#   跨架构构建使用 build.sh 的 --platform 参数。
#
# 语言运行时:
#   Node.js — nvm (版本管理器，构建时预装 LTS)
#   Python  — 系统 python3 + pip + venv
#   Go      — 官方二进制 (/usr/local/go)
#   Rust    — rustup (版本管理器)
#
#   不包含: Java, .NET, PHP, Ruby
# ============================================================
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ============================================================
# 系统工具
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep \
    fd-find \
    bat \
    htop \
    tmux \
    jq \
    tree \
    unzip \
    zip \
    less \
    man-db \
    build-essential \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
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
    && nvm alias default 'lts/*'

# ============================================================
# Python — 系统 python3 + pip + venv
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Go — 官方二进制 (ARG TARGETARCH 自动匹配 arm64/amd64)
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
# Shell 初始化 — init-env.sh 统一管理所有版本管理器激活
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

- [ ] **Step 2: 验证 Dockerfile 无语法错误**

```bash
docker build --dry-run --file .devcontainer/Dockerfile . 2>&1 | head -5 || true
```

> 注：`--dry-run` 在某些 Docker 版本不可用。若报 "unknown flag"，使用 `head -5 .devcontainer/Dockerfile` 确认 FROM 行语法正确即可。

---

### Task 2: 创建 init-env.sh

**Files:**
- Create: `.devcontainer/init-env.sh`

- [ ] **Step 1: 写入 init-env.sh**

```bash
#!/usr/bin/env bash
# ============================================================
# init-env.sh — 统一的 Shell 环境初始化
#
# 被 ~/.zshrc 和 ~/.bashrc 自动 source。
# 同时被 devcontainer.json 的 postCreateCommand 调用。
#
# 确保所有版本管理器在新 Shell 中正确激活。
# 幂等设计: 重复 source 安全。
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

- [ ] **Step 2: 添加可执行权限**

```bash
chmod +x .devcontainer/init-env.sh
```

- [ ] **Step 3: 验证语法**

```bash
bash -n .devcontainer/init-env.sh
```

Expected: 无输出（语法正确）。

---

### Task 3: 精简 devcontainer.json — 移除语言 Features

**Files:**
- Modify: `.devcontainer/devcontainer.json`（Features 块 + postCreateCommand）

- [ ] **Step 1: 替换 Features 块**

定位 `"features": {` 到对应的 `}` 块，替换为精简版本。

**查找的旧文本（第 77–116 行）：**

```jsonc
  "features": {

    // Docker-out-of-Docker: 将宿主机的 docker socket 挂载到容器内
    //   容器内执行 docker 命令时实际操作宿主机的 Docker daemon,
    //   共享镜像缓存,性能优于 Docker-in-Docker,无需特权模式。
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},

    // Node.js: LTS 版本 + pnpm 包管理器
    "ghcr.io/devcontainers/features/node:1": {
      "version": "lts",
      "pnpm": true
    },

    // Python: 最新版本
    "ghcr.io/devcontainers/features/python:1": {
      "version": "latest"
    },

    // Go: 最新版本
    "ghcr.io/devcontainers/features/go:1": {
      "version": "latest"
    },

    // Rust: 最新版本
    "ghcr.io/devcontainers/features/rust:1": {
      "version": "latest"
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
```

**替换为：**

```jsonc
  "features": {

    // Docker-out-of-Docker: 将宿主机的 docker socket 挂载到容器内
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {},

    // Git: 自动从宿主机继承 user.name / user.email 配置
    "ghcr.io/devcontainers/features/git:1": {},

    // Common Utilities: Zsh / curl / git / less 等常用工具
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true,
      "configureZshAsDefaultShell": true,
      "username": "vscode",
      "uid": "1000"
    }

    // 语言运行时 (Node/Python/Go/Rust) 不在此处配置。
    // 它们已通过版本管理器预装在 Dockerfile 镜像层中，
    // 由 init-env.sh 在 Shell 启动时统一激活。
  },
```

> 注意：`common-utils:2` 后面的尾部逗号保留（JSONC 允许），方便后续加 Feature。

- [ ] **Step 2: 更新 postCreateCommand**

将第 162 行：

```jsonc
  "postCreateCommand": "echo 'Dev container ready.' && zsh"
```

替换为：

```jsonc
  "postCreateCommand": "source /usr/local/bin/init-env.sh && echo 'Dev container ready.' && zsh"
```

- [ ] **Step 3: 验证 JSON 结构完整性**

```bash
python3 -c "
import json, re
with open('.devcontainer/devcontainer.json') as f:
    text = f.read()
# 去掉 JSONC 注释
text = re.sub(r'//.*', '', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
json.loads(text)
print('JSON valid')
"
```

Expected: `JSON valid`

---

### Task 4: 更新 README.md

**Files:**
- Modify: `README.md`（运行时说明 + 文件结构表 + 故障排除）

- [ ] **Step 1: 替换"语言运行时"章节（第 5–14 行）**

**旧文本：**

```markdown
## 语言运行时

通过微软 Dev Container Features 按需安装，不写入镜像：

| 运行时 | Feature |
|--------|---------|
| Node.js (LTS) + pnpm | `ghcr.io/devcontainers/features/node:1` |
| Python (latest) | `ghcr.io/devcontainers/features/python:1` |
| Go (latest) | `ghcr.io/devcontainers/features/go:1` |
| Rust (latest) | `ghcr.io/devcontainers/features/rust:1` |
```

**替换为：**

```markdown
## 语言运行时

版本管理器预装在镜像层中，容器启动即用，运行时自由切换版本：

| 运行时 | 版本管理器 | 默认版本 | 切版本 |
|--------|-----------|---------|--------|
| Node.js | nvm | LTS (构建时最新) | `nvm use 22` |
| Python | 系统 python3 + pip + venv | Ubuntu 自带 | 通过 venv 隔离项目 |
| Go | 官方二进制 `/usr/local/go` | 1.23.4 | 改 Dockerfile 中 GO_VERSION 重建镜像 |
| Rust | rustup | stable | `rustup default nightly` |

各管理器常用命令见 [docs/version-managers.md](docs/version-managers.md)。
```

- [ ] **Step 2: 更新"文件结构与职责"表（第 144–150 行）**

**旧文本：**

```markdown
| `.devcontainer/Dockerfile` | 镜像定义 | 基于 `mcr.microsoft.com/devcontainers/base:ubuntu` (multi-arch)，补充 ripgrep/fd/bat 等 CLI 工具，配置 Zsh。语言运行时通过 Features 安装，不写入镜像 |
| `.devcontainer/devcontainer.json` | 容器配置 | 声明固定挂载（`kai-fa/projects`、`kai-fa/data`、`.ssh`、`.gitconfig`），配置微软 Features（Docker-out-of-Docker、Node + pnpm、Python、Go、Rust、Git），VS Code 插件和设置，`--network=host` |
| `scripts/build.sh` | 宿主机脚本 | 调用 `docker build` 构建 `safe-agent-dev:latest` 镜像。默认自动检测架构，支持 `--platform` 指定跨架构构建 |
| `scripts/start.sh` | 宿主机脚本 | 按容器名管理生命周期：创建新容器（含固定挂载 + 专属工作区）、复用已有容器、强制重建（`-f`）、进入容器 Shell。支持 `--platform` 透传给 `build.sh` |
| `README.md` | 文档 | 前置要求、架构说明、快速开始、多容器使用、路径自定义、故障排除 |
```

**替换为：**

```markdown
| `.devcontainer/Dockerfile` | 镜像定义 | 基于 `base:ubuntu` (multi-arch)，安装 CLI 工具 + 版本管理器 (nvm / python3 / Go / rustup)，COPY init-env.sh，配置 Zsh。不包含 Java/.NET/PHP/Ruby |
| `.devcontainer/init-env.sh` | Shell 初始化 | 统一激活所有版本管理器（nvm / Go PATH / rustup），被 .zshrc、.bashrc、postCreateCommand 三处 source |
| `.devcontainer/devcontainer.json` | 容器配置 | 固定挂载 + 容器级 Features（Docker-out-of-Docker、Git、common-utils）+ VS Code 设置 |
| `scripts/build.sh` | 宿主机脚本 | 构建 `safe-agent-dev:latest`，默认自动检测架构，支持 `--platform` |
| `scripts/start.sh` | 宿主机脚本 | 容器生命周期管理（创建/复用/强制重建/进入），`-f` + `--platform` 透传 |
| `README.md` | 文档 | 前置要求、架构说明、快速开始、多容器使用、故障排除 |
| `docs/version-managers.md` | 参考 | nvm / pip / go / rustup 常用命令速查 |
```

- [ ] **Step 3: 故障排除表新增一条**

在第 140 行 "Apple Silicon 上拉取报..." 之后添加：

```markdown
| 容器内 `node`/`cargo` 等命令找不到 | init-env.sh 未 source | 手动执行 `source /usr/local/bin/init-env.sh` |

---

### 验证清单

全部 Task 完成后，执行以下验证：

- [ ] **验证文件结构**

```bash
find . -type f ! -path './.git/*' ! -path './docs/superpowers/*' ! -path './.claude/*' | sort
```

Expected:

```
./.devcontainer/Dockerfile
./.devcontainer/devcontainer.json
./.devcontainer/init-env.sh
./README.md
./docs/version-managers.md
./scripts/build.sh
./scripts/start.sh
```

- [ ] **验证 init-env.sh 可执行**

```bash
test -x .devcontainer/init-env.sh && echo "OK: executable" || echo "FAIL: not executable"
```

Expected: `OK: executable`

- [ ] **验证构建成功**

```bash
./scripts/build.sh
```

Expected: 构建成功，无错误退出。

- [ ] **验证容器内运行时可用**

```bash
# 启动测试容器
./scripts/start.sh v3-test ~/kai-fa/projects
```

在容器内执行：

```bash
source /usr/local/bin/init-env.sh
node -v    && echo "node OK"    || echo "node FAIL"
python3 -V && echo "python OK"  || echo "python FAIL"
go version && echo "go OK"      || echo "go FAIL"
rustc -V   && echo "rustc OK"   || echo "rustc FAIL"
cargo -V   && echo "cargo OK"   || echo "cargo FAIL"
nvm --version && echo "nvm OK"  || echo "nvm FAIL"
rustup -V  && echo "rustup OK"  || echo "rustup FAIL"
```

Expected: 全部 `OK`，无 FAIL。

退出容器并清理：

```bash
exit                           # 退出
docker rm -f v3-test           # 清理测试容器
```
