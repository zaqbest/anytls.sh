# AnyTLS 一键安装脚本

一个用于快速部署 [AnyTLS](https://github.com/anytls/anytls-go) 服务端的自动化脚本。

## ✨ 功能特性

- ✅ **多系统兼容**：CentOS / RHEL / Rocky / AlmaLinux / Ubuntu / Debian / Alpine
- ✅ **多架构支持**：amd64 / arm64 / armv7
- ✅ **开机自启**：自动配置 systemd（主流发行版）或 openrc（Alpine）
- ✅ **自动关闭防火墙**：firewalld / ufw / iptables
- ✅ **参数可配置**：端口、密码均可自定义，也可使用默认值
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
# 使用默认端口和密码
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zaqbest/anytls.sh/main/install.sh)"

# 指定端口和密码（注意 _ 是必需的占位符）
sh -c "$(curl -fsSL https://raw.githubusercontent.com/zaqbest/anytls/main/install.sh)" _ -p 8443 -s mypassword

# 使用自定义域名
sh -c "$(curl -fsSL https://install-anytls.zaqbest.com)"
```

### 方式二：本地下载执行

```bash
# 下载脚本
curl -fsSL -o install.sh https://raw.githubusercontent.com/zaqbest/anytls.sh/main/install.sh
chmod +x install.sh

# 默认安装
sudo bash install.sh

# 指定端口
sudo bash install.sh -p 8443

# 指定密码
sudo bash install.sh -s mypassword

# 同时指定端口和密码
sudo bash install.sh -p 8443 -s mypassword
```

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