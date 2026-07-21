#!/usr/bin/env bash
#
# install-anytls.sh - AnyTLS 一键安装脚本
#
# 支持系统: CentOS / Ubuntu / Debian / Alpine
# 用法:
#   bash install-anytls.sh                          # 默认端口54821，默认密码
#   bash install-anytls.sh -p 8443 -s mypassword    # 指定端口和密码
#   bash install-anytls.sh --uninstall              # 卸载
#
# 一键安装:
#   sh -c "$(curl -fsSL https://your-domain/install-anytls.sh)"
#   sh -c "$(curl -fsSL https://your-domain/install-anytls.sh)" _ -p 8443 -s mypass
#

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# ==================== 默认配置 ====================
DEFAULT_PORT="54821"
DEFAULT_PASSWORD="k8X9mP3vL7qR2wT5"

INSTALL_DIR="/opt/anytls"
BIN_FILE="${INSTALL_DIR}/anytls-server"
CONFIG_FILE="${INSTALL_DIR}/config.json"
LOG_FILE="${INSTALL_DIR}/anytls.log"

SYSTEMD_FILE="/etc/systemd/system/anytls.service"
OPENRC_FILE="/etc/init.d/anytls"

GITHUB_REPO="anytls/anytls-go"

# ==================== 变量 ====================
PORT=""
PASSWORD=""
ACTION="install"

OS=""
ARCH=""
INIT_SYSTEM=""

# ==================== 工具函数 ====================
log_info()    { echo -e "${GREEN}[INFO]${PLAIN} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
log_error()   { echo -e "${RED}[ERROR]${PLAIN} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${PLAIN} $*"; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "此脚本必须以 root 用户运行！请使用 sudo 或切换到 root。"
        exit 1
    fi
}

# ==================== 参数解析 ====================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -s|--password)
                PASSWORD="$2"
                shift 2
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_warn "未知参数: $1"
                shift
                ;;
        esac
    done

    [ -z "$PORT" ] && PORT="$DEFAULT_PORT"
    [ -z "$PASSWORD" ] && PASSWORD="$DEFAULT_PASSWORD"
}

show_help() {
    cat <<EOF
AnyTLS 一键安装脚本

用法:
    bash install-anytls.sh [选项]

选项:
    -p, --port      <端口>       指定监听端口 (默认: ${DEFAULT_PORT})
    -s, --password  <密码>       指定连接密码 (默认: ${DEFAULT_PASSWORD})
    --uninstall                  卸载 AnyTLS
    -h, --help                   显示此帮助信息

示例:
    bash install-anytls.sh
    bash install-anytls.sh -p 8443 -s mypassword
    bash install-anytls.sh --uninstall

一键安装:
    sh -c "\$(curl -fsSL https://your-domain/install-anytls.sh)"
    sh -c "\$(curl -fsSL https://your-domain/install-anytls.sh)" _ -p 8443 -s mypass
EOF
}

# ==================== 系统检测 ====================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            centos|rhel|rocky|almalinux|fedora)
                OS="centos"
                ;;
            ubuntu|debian)
                OS="ubuntu"
                ;;
            alpine)
                OS="alpine"
                ;;
            *)
                if echo "$ID_LIKE" | grep -qi "rhel\|centos\|fedora"; then
                    OS="centos"
                elif echo "$ID_LIKE" | grep -qi "debian"; then
                    OS="ubuntu"
                else
                    log_error "不支持的系统: $ID"
                    exit 1
                fi
                ;;
        esac
    else
        log_error "无法检测系统类型，缺少 /etc/os-release"
        exit 1
    fi

    if [ "$OS" = "alpine" ]; then
        INIT_SYSTEM="openrc"
    else
        if command -v systemctl >/dev/null 2>&1; then
            INIT_SYSTEM="systemd"
        else
            log_error "未找到 systemd，暂不支持此系统"
            exit 1
        fi
    fi

    log_info "检测到系统: ${OS}，init 系统: ${INIT_SYSTEM}"
}

detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l|armv7)
            ARCH="armv7"
            ;;
        *)
            log_error "不支持的架构: $machine"
            exit 1
            ;;
    esac
    log_info "检测到架构: ${ARCH}"
}

# ==================== 安装依赖 ====================
install_dependencies() {
    log_info "安装必要依赖..."
    case "$OS" in
        centos)
            yum install -y curl wget unzip tar >/dev/null 2>&1 || true
            ;;
        ubuntu)
            apt-get update -y >/dev/null 2>&1 || true
            apt-get install -y curl wget unzip tar >/dev/null 2>&1 || true
            ;;
        alpine)
            apk update >/dev/null 2>&1 || true
            apk add --no-cache curl wget unzip tar bash >/dev/null 2>&1 || true
            ;;
    esac
}

# ==================== 关闭防火墙 ====================
disable_firewall() {
    log_info "关闭防火墙..."
    case "$OS" in
        centos)
            if command -v firewall-cmd >/dev/null 2>&1; then
                systemctl stop firewalld 2>/dev/null || true
                systemctl disable firewalld 2>/dev/null || true
                log_success "firewalld 已关闭"
            fi
            ;;
        ubuntu)
            if command -v ufw >/dev/null 2>&1; then
                ufw disable 2>/dev/null || true
                log_success "ufw 已关闭"
            fi
            ;;
        alpine)
            if command -v rc-service >/dev/null 2>&1; then
                rc-service iptables stop 2>/dev/null || true
                rc-update del iptables 2>/dev/null || true
                rc-service ip6tables stop 2>/dev/null || true
                rc-update del ip6tables 2>/dev/null || true
                log_success "iptables 服务已关闭"
            fi
            ;;
    esac
}

# ==================== 下载安装 ====================
get_latest_version() {
    local version
    version="$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | head -n1 \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
    echo "$version"
}

download_anytls() {
    log_info "获取 AnyTLS 最新版本..."
    local version
    version="$(get_latest_version)"
    if [ -z "$version" ]; then
        log_error "无法获取最新版本，请检查网络或 GitHub API 限制"
        exit 1
    fi
    log_info "最新版本: ${version}"

    local version_no_v="${version#v}"
    local filename="anytls_${version_no_v}_linux_${ARCH}.zip"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    log_info "下载: ${download_url}"

    if ! curl -fsSL -o "${tmp_dir}/${filename}" "${download_url}"; then
        log_error "下载失败: ${download_url}"
        rm -rf "$tmp_dir"
        exit 1
    fi

    log_info "解压文件..."
    mkdir -p "$INSTALL_DIR"
    unzip -oq "${tmp_dir}/${filename}" -d "$tmp_dir"

    local server_bin
    server_bin="$(find "$tmp_dir" -type f -name 'anytls-server*' ! -name '*.zip' | head -n1)"
    if [ -z "$server_bin" ]; then
        log_error "解压后未找到 anytls-server 二进制文件"
        rm -rf "$tmp_dir"
        exit 1
    fi

    cp -f "$server_bin" "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -rf "$tmp_dir"
    log_success "AnyTLS 二进制已安装到 ${BIN_FILE}"
}

# ==================== 生成配置文件 ====================
generate_config() {
    log_info "生成配置文件 ${CONFIG_FILE}"
    mkdir -p "$INSTALL_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
    "listen": "0.0.0.0:${PORT}",
    "password": "${PASSWORD}"
}
EOF
    chmod 644 "$CONFIG_FILE"
    touch "$LOG_FILE"
}

# ==================== 创建 systemd 服务 ====================
# ==================== 创建 systemd 服务 ====================
create_systemd_service() {
    log_info "创建 systemd 服务..."
    cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_FILE} -l 0.0.0.0:${PORT} -p ${PASSWORD}
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable anytls >/dev/null 2>&1
    systemctl restart anytls
    sleep 2

    if systemctl is-active --quiet anytls; then
        log_success "AnyTLS 服务已启动并设置为开机自启"
    else
        log_error "AnyTLS 服务启动失败，请查看日志:"
        log_error "  journalctl -u anytls -n 50"
        log_error "  tail -n 50 ${LOG_FILE}"
        exit 1
    fi
}

# ==================== 创建 openrc 服务 ====================
create_openrc_service() {
    log_info "创建 openrc 服务..."
    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run

name="anytls"
description="AnyTLS Server"

command="${BIN_FILE}"
command_args="-l 0.0.0.0:${PORT} -p ${PASSWORD}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"

directory="${INSTALL_DIR}"

depend() {
    need net
    after firewall
}
EOF
    chmod +x "$OPENRC_FILE"

    rc-update add anytls default >/dev/null 2>&1
    rc-service anytls restart >/dev/null 2>&1 || rc-service anytls start
    sleep 2

    if rc-service anytls status >/dev/null 2>&1; then
        log_success "AnyTLS 服务已启动并设置为开机自启"
    else
        log_error "AnyTLS 服务启动失败，请查看日志: ${LOG_FILE}"
        exit 1
    fi
}

create_service() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        create_systemd_service
    else
        create_openrc_service
    fi
}

# ==================== 停止/删除服务 ====================
stop_and_remove_service() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files 2>/dev/null | grep -q '^anytls\.service'; then
            systemctl stop anytls 2>/dev/null || true
            systemctl disable anytls 2>/dev/null || true
        fi
        rm -f "$SYSTEMD_FILE"
        systemctl daemon-reload 2>/dev/null || true
    fi

    if command -v rc-service >/dev/null 2>&1; then
        rc-service anytls stop 2>/dev/null || true
        rc-update del anytls 2>/dev/null || true
        rm -f "$OPENRC_FILE"
    fi
}

# ==================== 卸载 ====================
uninstall_anytls() {
    log_warn "开始卸载 AnyTLS..."
    stop_and_remove_service
    rm -rf "$INSTALL_DIR"
    log_success "AnyTLS 已完全卸载"
}

# ==================== 获取公网 IP ====================
get_public_ip() {
    local ip
    ip="$(curl -fsSL -m 5 https://api.ipify.org 2>/dev/null || \
          curl -fsSL -m 5 https://ifconfig.me 2>/dev/null || \
          curl -fsSL -m 5 https://ipinfo.io/ip 2>/dev/null)"
    [ -z "$ip" ] && ip="<your-server-ip>"
    echo "$ip"
}

# ==================== 显示安装信息 ====================
show_result() {
    local public_ip
    public_ip="$(get_public_ip)"

    echo
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}     AnyTLS 安装成功！${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e " ${BLUE}服务器地址${PLAIN} : ${public_ip}"
    echo -e " ${BLUE}端口${PLAIN}       : ${PORT}"
    echo -e " ${BLUE}密码${PLAIN}       : ${PASSWORD}"
    echo -e " ${BLUE}安装目录${PLAIN}   : ${INSTALL_DIR}"
    echo -e " ${BLUE}配置文件${PLAIN}   : ${CONFIG_FILE}"
    echo -e " ${BLUE}日志文件${PLAIN}   : ${LOG_FILE}"
    echo -e "${GREEN}------------------------------------------------${PLAIN}"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        echo -e " 服务管理:"
        echo -e "   启动 : ${YELLOW}systemctl start anytls${PLAIN}"
        echo -e "   停止 : ${YELLOW}systemctl stop anytls${PLAIN}"
        echo -e "   重启 : ${YELLOW}systemctl restart anytls${PLAIN}"
        echo -e "   状态 : ${YELLOW}systemctl status anytls${PLAIN}"
        echo -e "   日志 : ${YELLOW}journalctl -u anytls -f${PLAIN}"
    else
        echo -e " 服务管理:"
        echo -e "   启动 : ${YELLOW}rc-service anytls start${PLAIN}"
        echo -e "   停止 : ${YELLOW}rc-service anytls stop${PLAIN}"
        echo -e "   重启 : ${YELLOW}rc-service anytls restart${PLAIN}"
        echo -e "   状态 : ${YELLOW}rc-service anytls status${PLAIN}"
    fi
    echo -e " 卸载 : ${YELLOW}bash install-anytls.sh --uninstall${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo
}

# ==================== 主流程 ====================
main() {
    parse_args "$@"
    check_root
    detect_os
    detect_arch

    if [ "$ACTION" = "uninstall" ]; then
        uninstall_anytls
        exit 0
    fi

    install_dependencies
    disable_firewall
    download_anytls
    generate_config
    create_service
    show_result
}

main "$@"
