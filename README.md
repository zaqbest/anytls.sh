# AnyTLS 一键安装脚本

一个用于快速部署 AnyTLS 服务端的自动化脚本，同时支持两种实现：

- 🐹 [anytls-go](https://github.com/anytls/anytls-go)（**官方 Go 版, 默认**）
- 🦀 [anytls-rs](https://github.com/ssrlive/anytls-rs)（社区 Rust 版, 二进制更小、更省内存）

## ✨ 功能特性

- ✅ **双实现可选**：Go 官方版（默认，推荐）/ Rust 社区版（低配设备友好）
- ✅ **交互式选择**：安装时可选择实现，也可通过参数指定
- ✅ **多系统兼容**：CentOS / RHEL / Rocky / AlmaLinux / Ubuntu / Debian / Alpine
- ✅ **多架构支持**：amd64 / arm64 / armv7
- ✅ **开机自启**：自动配置 systemd（主流发行版）或 openrc（Alpine）
- ✅ **自动关闭防火墙**：firewalld / ufw / iptables
- ✅ **参数可配置**：端口、密码、实现类型均可自定义
- ✅ **一键卸载**：`--uninstall` 参数快速清理
- ✅ **一键安装**：支持 `sh -c "$(curl ...)"` 远程执行

## 📦 默认配置

| 项目 | 值 |
|------|-----|
| 默认端口 | `54821` |
| 默认密码 | `k8X9mP3vL7qR2wT5` |
| 安装目录 | `/opt/anytls/` |
| 可执行文件 | `/opt/anytls/anytls-server` |
| 配置文件 | `/opt/anytls/config.json` |
| 日志文件 | `/opt/anytls/anytls.log` |

## 🚀 快速开始

### 方式一：一键远程安装（推荐）

将脚本托管到 GitHub 或自己的域名后，只需一行命令即可安装：

```bash
# 交互式安装，会提示选择 Go / Rust 版
sh -c "$(curl -fsSL https://install-anytls.zaqbest.com)"

# 指定端口和密码（注意 _ 是必需的占位符）
sh -c "$(curl -fsSL https://install-anytls.zaqbest.com)" _ -p 8443 -s mypassword

# 直接使用 Rust 版（非交互）
sh -c "$(curl -fsSL https://install-anytls.zaqbest.com)" _ -i rust -y

# 直接使用 Go 版（非交互，等价于默认）
sh -c "$(curl -fsSL https://install-anytls.zaqbest.com)" _ -i go -y
```

### 方式二：本地下载执行

```bash
# 下载脚本
curl -fsSL -o install.sh https://install-anytls.zaqbest.com 
chmod +x install.sh

# 交互式安装（会提示选择实现）
sudo bash install.sh

# 指定 Rust 版
sudo bash install.sh -i rust

# 指定 Go 版 + 端口 + 密码
sudo bash install.sh -i go -p 8443 -s mypassword

# 非交互模式使用默认（Go 版）
sudo bash install.sh -y
```

## 🔀 Go 版 vs Rust 版

| 维度 | Go 版 (anytls-go) | Rust 版 (anytls-rs) |
|------|-------------------|---------------------|
| 地位 | **官方参考实现** | 社区第三方移植 |
| 协议更新 | 第一时间跟进 | 跟随官方，可能有滞后 |
| 二进制体积 | 8-12 MB | 3-5 MB |
| 内存占用 | 中等（有 GC） | 更低（无 GC） |
| 平台/架构支持 | 非常齐全 | 相对较少 |
| 兼容性 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 稳定性 | 用户验证多 | Rust 内存安全 |

**建议**：
- 👉 **普通 VPS**：用 **Go 版**（默认），最稳最省心
- 👉 **低配设备 / 路由器 / 追求极致性能**：可选 **Rust 版**

## ⚙️ 所有命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-p, --port <端口>` | 监听端口 | `54821` |
| `-s, --password <密码>` | 连接密码 | `k8X9mP3vL7qR2wT5` |
| `-i, --impl <go\|rust>` | 服务端实现 | `go` |
| `-y, --yes` | 非交互模式（使用默认实现） | - |
| `--uninstall` | 卸载 | - |
| `-h, --help` | 显示帮助 | - |

## 🗑️ 卸载

```bash
sudo bash install.sh --uninstall
```

## 🔧 服务管理

### systemd (CentOS / Ubuntu / Debian)

```bash
systemctl start anytls      # 启动
systemctl stop anytls       # 停止
systemctl restart anytls    # 重启
systemctl status anytls     # 查看状态
journalctl -u anytls -f     # 查看日志
```

### openrc (Alpine)

```bash
rc-service anytls start     # 启动
rc-service anytls stop      # 停止
rc-service anytls restart   # 重启
rc-service anytls status    # 查看状态
tail -f /opt/anytls/anytls.log  # 查看日志
```

## ❓ 常见问题

### 1. 一键安装如何传参？

`sh -c` 方式传参需要一个占位符（约定用 `_`）作为 `$0`：
```bash
sh -c "$(curl -fsSL https://xxx/install.sh)" _ -p 8443 -s mypass
```

### 2. GitHub API 限流怎么办？

脚本通过 GitHub API 获取最新版本，未登录用户每小时 60 次。如遇限流：
- 稍后重试
- 或修改脚本中 `get_latest_version` 手动指定版本号

### 3. 如何查看运行日志？

- 日志文件：`/opt/anytls/anytls.log`
- systemd 日志：`journalctl -u anytls -f`

## 📄 License

MIT