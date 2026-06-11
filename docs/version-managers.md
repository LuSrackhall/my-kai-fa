# 版本管理器常用命令速查

本容器预装了以下版本管理器，可在运行时自由切换版本，无需重建镜像。

---

## Node.js — nvm

| 操作 | 命令 |
|------|------|
| 查看已安装的版本 | `nvm ls` |
| 查看可安装的 LTS 版本 | `nvm ls-remote --lts` |
| 查看所有可安装版本 | `nvm ls-remote` |
| 安装指定版本 | `nvm install 22` |
| 安装最新 LTS | `nvm install --lts` |
| 切换到指定版本 | `nvm use 22` |
| 设置默认版本（新 Shell 自动生效） | `nvm alias default 22` |
| 查看当前版本 | `node -v` |
| 卸载指定版本 | `nvm uninstall 18` |
| 查看 nvm 版本 | `nvm --version` |

**示例：同时安装两个版本并切换**

```bash
nvm install 20        # 装 Node 20
nvm install 22        # 装 Node 22
nvm use 22            # 切到 22
node -v               # → v22.x.x
nvm use 20            # 切到 20
node -v               # → v20.x.x
nvm alias default 22  # 新终端默认用 22
```

---

## Python

| 操作 | 命令 |
|------|------|
| 查看版本 | `python3 --version` |
| 安装 pip 包 | `pip3 install <package>` |
| 查看已安装的包 | `pip3 list` |
| 创建虚拟环境 | `python3 -m venv .venv` |
| 激活虚拟环境 | `source .venv/bin/activate` |
| 退出虚拟环境 | `deactivate` |
| 删除虚拟环境 | `rm -rf .venv` |

**示例：项目中用虚拟环境**

```bash
cd my-python-project
python3 -m venv .venv       # 创建
source .venv/bin/activate    # 激活
pip install requests numpy   # 装依赖
deactivate                   # 退出
```

---

## Go

| 操作 | 命令 |
|------|------|
| 查看版本 | `go version` |
| 查看环境变量 | `go env` |
| 初始化模块 | `go mod init <module-name>` |
| 下载依赖 | `go mod tidy` |
| 构建 | `go build ./...` |
| 构建并输出到指定路径 | `go build -o ./bin/app ./cmd/app` |
| 运行 | `go run main.go` |
| 运行测试 | `go test ./...` |
| 安装 CLI 工具 | `go install <package>@latest` |

> **Go 版本切换：** Go 通过 `/usr/local/go` 安装，未使用版本管理器。如需切换版本，修改 Dockerfile 中 `GO_VERSION` 参数后重建镜像。
>
> **安装的 Go 工具**（`go install`）放在 `~/go/bin`，已在 PATH 中，直接可用。

---

## Rust — rustup

| 操作 | 命令 |
|------|------|
| 查看已安装工具链 | `rustup show` |
| 查看可用工具链 | `rustup toolchain list` |
| 安装 stable 工具链 | `rustup install stable` |
| 安装 nightly 工具链 | `rustup install nightly` |
| 切换默认工具链 | `rustup default stable` |
| 临时使用某工具链 | `rustup run nightly cargo build` |
| 更新所有工具链 | `rustup update` |
| 查看版本 | `rustc --version` |
| 查看 cargo 版本 | `cargo --version` |
| 添加组件 | `rustup component add clippy rustfmt` |
| 添加编译目标 | `rustup target add wasm32-unknown-unknown` |

**示例：项目级工具链**

```bash
cd my-rust-project
rustup override set nightly    # 此项目用 nightly
rustup override unset          # 恢复默认
```

**常用 cargo 命令**

| 操作 | 命令 |
|------|------|
| 新建项目 | `cargo new my-app` |
| 构建（debug） | `cargo build` |
| 构建（release） | `cargo build --release` |
| 运行 | `cargo run` |
| 测试 | `cargo test` |
| 代码检查 | `cargo clippy` |
| 格式化 | `cargo fmt` |
| 安装 CLI 工具 | `cargo install <crate>` |
| 更新依赖 | `cargo update` |

---

## Shell 环境

所有版本管理器通过 `~/.zshrc` 在每次打开终端时自动激活。

如果某个命令找不到（如 `node`、`cargo`），手动执行：

```bash
source /usr/local/bin/init-env.sh
```

Zsh 别名：

| 别名 | 实际命令 | 用途 |
|------|---------|------|
| `ll` | `ls -alh` | 详细列表 |
| `fd` | `fdfind` | 快速文件查找 |
| `bat` | `batcat` | 语法高亮查看文件 |
