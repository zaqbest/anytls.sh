#!/usr/bin/env bash
#
# install-anytls.sh - AnyTLS 一键安装脚本
#
# 支持系统: CentOS / Ubuntu / Debian / Alpine
# 支持实现: go (官方 anytls-go, 默认) / rust (社区 anytls-rs)
#
# 用法:
#   bash install-anytls.sh                          # 默认端口54821，默认密码，Go 版
#   bash install-anytls.sh -p 8443 -s mypassword    # 指定端口和密码
#   bash install-anytls.sh -i rust                  # 使用 Rust 实现
#   bash install-anytls.sh -i go                    # 使用 Go 实现（默认）
#   bash install-anytls.sh --uninstall              # 卸载
#
# 一键安装:
#   sh -c "$(curl -fsSL https://your-domain/install-anytls.sh)"
#   sh -c "$(curl -fsSL https://your-domain/install-anytls.sh)" _ -p 8443 -s mypass
#   sh -c "$(curl -fsSL https://your-domain/install-anytls.sh)" _ -i rust -y
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

DEFAULT_PORT="54821"
DEFAULT_PASSWORD="k8X9mP3vL7qR2wT5"
DEFAULT_IMPL="go"

INSTALL_DIR="/opt/anytls"
BIN_FILE="${INSTALL_DIR}/anytls-server"
CONFIG_FILE="${INSTALL_DIR}/config.json"
LOG_FILE="${INSTALL_DIR}/anytls.log"
IMPL_FILE="${INSTALL_DIR}/.impl"

SYSTEMD_FILE="/etc/systemd/system/anytls.service"
OPENRC_FILE="/etc/init.d/anytls"

GITHUB_REPO_GO="anytls/anytls-go"
GITHUB_REPO_RUST="ssrlive/anytls-rs"

PORT=""
PASSWORD=""
IMPL=""
ACTION="install"
NON_INTERACTIVE="0"

OS=""
ARCH=""
INIT_SYSTEM=""

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

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--port)
                PORT="$2"; shift 2 ;;
            -s|--password)
                PASSWORD="$2"; shift 2 ;;
            -i|--impl)
                IMPL="$2"; NON_INTERACTIVE="1"; shift 2 ;;
            -y|--yes|--non-interactive)
                NON_INTERACTIVE="1"; shift ;;
            --uninstall)
                ACTION="uninstall"; shift ;;
            -h|--help)
                show_help; exit 0 ;;
            *)
                log_warn "未知参数: $1"; shift ;;
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
    -i, --impl      <go|rust>    选择实现: go=官方Go版, rust=社区Rust版 (默认: ${DEFAULT_IMPL})
    -y, --yes                    非交互模式, 使用默认实现
    --uninstall                  卸载 AnyTLS
    -h, --help                   显示此帮助信息

示例:
    bash install-anytls.sh
    bash install-anytls.sh -p 8443 -s mypassword
    bash install-anytls.sh -i rust
    bash install-anytls.sh --uninstall
EOF
}

choose_impl() {
    if [ -n "$IMPL" ]; then
        return
    fi

    if [ "$NON_INTERACTIVE" = "1" ]; then
        IMPL="$DEFAULT_IMPL"
        log_info "非交互模式，使用默认实现: ${IMPL}"
        return
    fi

    local tty_dev=""
    if [ -e /dev/tty ]; then
        tty_dev="/dev/tty"
    elif [ -t 0 ]; then
        tty_dev=""
    else
        IMPL="$DEFAULT_IMPL"
        log_info "无 TTY，使用默认实现: ${IMPL}"
        return
    fi

    echo
    echo -e "${BLUE}请选择 AnyTLS 服务端实现:${PLAIN}"
    echo -e "  ${GREEN}1)${PLAIN} Go   版 (官方 anytls-go)     ${YELLOW}[默认, 推荐]${PLAIN}"
    echo -e "       优点: 官方维护, 协议更新及时, 兼容性最佳, 多架构齐全"
    echo -e "  ${GREEN}2)${PLAIN} Rust 版 (社区 anytls-rs)"
    echo -e "       优点: 二进制更小, 内存占用更低, 适合低配设备"
    echo
    printf "请输入选项 [1-2] (回车使用默认 1): "

    local choice=""
    if [ -n "$tty_dev" ]; then
        read -r choice <"$tty_dev" || choice=""
    else
        read -r choice || choice=""
    fi

    case "$choice" in
        2|rust|Rust|RUST)
            IMPL="rust" ;;
        *)
            IMPL="go" ;;
    esac
    log_info "已选择实现: ${IMPL}"
}

validate_impl() {
    case "$IMPL" in
        go|rust) ;;
        *)
            log_error "无效的实现类型: ${IMPL} (可选: go, rust)"
            exit 1
            ;;
    esac
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            centos|rhel|rocky|almalinux|fedora)
                OS="centos" ;;
            ubuntu|debian)
                OS="ubuntu" ;;
            alpine)
                OS="alpine" ;;
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
            ARCH="amd64" ;;
        aarch64|arm64)
            ARCH="arm64" ;;
        armv7l|armv7)
            ARCH="armv7" ;;
        *)
            log_error "不支持的架构: $machine"
            exit 1
            ;;
    esac
    log_info "检测到架构: ${ARCH}"
}

rust_target_triple() {
    case "$ARCH" in
        amd64) echo "x86_64-unknown-linux-musl" ;;
        arm64) echo "aarch64-unknown-linux-musl" ;;
        armv7) echo "armv7-unknown-linux-musleabihf" ;;
        *)     echo "" ;;
    esac
}

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

get_latest_version() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | head -n1 \
        | cut -d '"' -f 4
}

download_anytls_go() {
    log_info "获取 AnyTLS (Go 版) 最新版本..."
    local version
    version="$(get_latest_version "$GITHUB_REPO_GO")"
    if [ -z "$version" ]; then
        log_error "无法获取最新版本，请检查网络或 GitHub API 限制"
        exit 1
    fi
    log_info "最新版本: ${version}"

    local version_no_v="${version#v}"
    local filename="anytls_${version_no_v}_linux_${ARCH}.zip"
local download_url="https://github.com/${GITHUB_REPO_GO}/releases/download/${version}/${filename}"

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
    log_success "AnyTLS (Go 版) 二进制已安装到 ${BIN_FILE}"
}

download_anytls_rust() {
    log_info "获取 AnyTLS (Rust 版) 最新版本..."
    local version
    version="$(get_latest_version "$GITHUB_REPO_RUST")"
    if [ -z "$version" ]; then
        log_error "无法获取最新版本，请检查网络或 GitHub API 限制"
        exit 1
    fi
    log_info "最新版本: ${version}"

    local triple
    triple="$(rust_target_triple)"
    if [ -z "$triple" ]; then
        log_error "Rust 版不支持当前架构: ${ARCH}"
        exit 1
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO_RUST}/releases/tags/${version}"
    log_info "查询资源列表..."

    local assets_json
    assets_json="$(curl -fsSL "$api_url" 2>/dev/null || true)"
    if [ -z "$assets_json" ]; then
        log_error "无法获取 release 资源列表"
        exit 1
    fi

    local download_url
    download_url="$(echo "$assets_json" \
        | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | cut -d '"' -f 4 \
        | grep -E "${triple}\\.(zip|tar\\.gz|tar\\.xz)$" \
        | head -n1)"

    if [ -z "$download_url" ]; then
        log_warn "未找到精确匹配 ${triple} 的资源，尝试宽松匹配..."
        local arch_pattern="${ARCH}"
        case "$ARCH" in
            amd64) arch_pattern="x86_64|amd64" ;;
            arm64) arch_pattern="aarch64|arm64" ;;
            armv7) arch_pattern="armv7|armhf" ;;
        esac
        download_url="$(echo "$assets_json" \
            | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' \
            | cut -d '"' -f 4 \
            | grep -iE "linux" \
            | grep -iE "${arch_pattern}" \
            | head -n1)"
    fi

    if [ -z "$download_url" ]; then
        log_error "未在 anytls-rs 的 release 中找到匹配 ${ARCH} 的 Linux 资源"
        log_error "请前往 https://github.com/${GITHUB_REPO_RUST}/releases 手动查看"
        exit 1
    fi

    local filename
    filename="$(basename "$download_url")"

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
    case "$filename" in
        *.zip)
            unzip -oq "${tmp_dir}/${filename}" -d "$tmp_dir"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "${tmp_dir}/${filename}" -C "$tmp_dir"
            ;;
        *.tar.xz)
            tar -xJf "${tmp_dir}/${filename}" -C "$tmp_dir"
            ;;
        *)
            log_error "未知的压缩格式: ${filename}"
            rm -rf "$tmp_dir"
            exit 1
            ;;
    esac

    local server_bin
    server_bin="$(find "$tmp_dir" -type f \( -name 'anytls-server*' -o -name 'anytls_server*' \) ! -name '*.zip' ! -name '*.tar*' | head -n1)"
    if [ -z "$server_bin" ]; then
        server_bin="$(find "$tmp_dir" -type f -name 'anytls*' ! -name '*.zip' ! -name '*.tar*' ! -iname '*client*' | head -n1)"
    fi
    if [ -z "$server_bin" ]; then
        log_error "解压后未找到 anytls-server 二进制文件"
        log_error "解压目录内容:"
        find "$tmp_dir" -type f | while read -r f; do log_error "  $f"; done
        rm -rf "$tmp_dir"
        exit 1
    fi

    cp -f "$server_bin" "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -rf "$tmp_dir"
    log_success "AnyTLS (Rust 版) 二进制已安装到 ${BIN_FILE}"
}

download_anytls() {
    if [ "$IMPL" = "rust" ]; then
        download_anytls_rust
    else
        download_anytls_go
    fi
    mkdir -p "$INSTALL_DIR"
    echo "$IMPL" > "$IMPL_FILE"
}

generate_config() {
    log_info "生成配置文件 ${CONFIG_FILE}"
    mkdir -p "$INSTALL_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
    "listen": "0.0.0.0:${PORT}",
    "password": "${PASSWORD}",
    "impl": "${IMPL}"
}
EOF
    chmod 644 "$CONFIG_FILE"
    touch "$LOG_FILE"
}

create_systemd_service() {
    log_info "创建 systemd 服务..."
    cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=AnyTLS Server (${IMPL})
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

create_openrc_service() {
    log_info "创建 openrc 服务..."
    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run

name="anytls"
description="AnyTLS Server (${IMPL})"

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

uninstall_anytls() {
    log_warn "开始卸载 AnyTLS..."
    stop_and_remove_service
    rm -rf "$INSTALL_DIR"
    log_success "AnyTLS 已完全卸载"
}

get_public_ip() {
    local ip
    ip="$(curl -fsSL -m 5 https://api.ipify.org 2>/dev/null || \
          curl -fsSL -m 5 https://ifconfig.me 2>/dev/null || \
          curl -fsSL -m 5 https://ipinfo.io/ip 2>/dev/null)"
    [ -z "$ip" ] && ip="<your-server-ip>"
    echo "$ip"
}

# 基于 IP 后 2 段生成 Surge 节点名前缀
node_prefix() {
    local ip="$1"
    local last2
    last2="$(echo "${ip}" | awk -F. '{print $3"-"$4}' 2>/dev/null || true)"
    if [ -z "${last2}" ] || [ "${last2}" = "-" ]; then
        echo "anytls"
    else
        echo "at-${last2}"
    fi
}

show_result() {
    local public_ip prefix
    public_ip="$(get_public_ip)"
    prefix="$(node_prefix "${public_ip}")"

    local impl_label="Go 官方版"
    [ "$IMPL" = "rust" ] && impl_label="Rust 社区版"

    echo
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}     AnyTLS 安装成功！${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e " ${BLUE}实现版本${PLAIN}   : ${impl_label} (${IMPL})"
    echo -e " ${BLUE}服务器地址${PLAIN} : ${public_ip}"
    echo -e " ${BLUE}端口${PLAIN}       : ${PORT}"
    echo -e " ${BLUE}密码${PLAIN}       : ${PASSWORD}"
    echo -e " ${BLUE}安装目录${PLAIN}   : ${INSTALL_DIR}"
    echo -e " ${BLUE}配置文件${PLAIN}   : ${CONFIG_FILE}"
    echo -e " ${BLUE}日志文件${PLAIN}   : ${LOG_FILE}"
    echo -e "${GREEN}------------------------------------------------${PLAIN}"
    echo -e "${YELLOW}# Surge / Stash / Loon [Proxy] 直接复制:${PLAIN}"
    echo "${prefix} = anytls, ${public_ip}, ${PORT}, password=${PASSWORD}, sni=bing.com, skip-cert-verify=true, udp-relay=true"
    echo
    echo -e "${YELLOW}# 通用 URL:${PLAIN}"
    echo "anytls://${PASSWORD}@${public_ip}:${PORT}/?sni=bing.com&insecure=1#${prefix}"
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

    # 同时写入客户端信息文件
    cat > "${INSTALL_DIR}/client_info.txt" <<CIEOF
  AnyTLS server info (client reference)
Server IP : ${public_ip}
Port      : ${PORT}
Password  : ${PASSWORD}

# Surge / Stash / Loon [Proxy] 直接复制:
${prefix} = anytls, ${public_ip}, ${PORT}, password=${PASSWORD}, sni=bing.com, skip-cert-verify=true, udp-relay=true

# 通用 URL:
anytls://${PASSWORD}@${public_ip}:${PORT}/?sni=bing.com&insecure=1#${prefix}
CIEOF
    chmod 600 "${INSTALL_DIR}/client_info.txt"
}

main() {
    parse_args "$@"
    check_root

    if [ "$ACTION" = "uninstall" ]; then
        uninstall_anytls
        exit 0
    fi

    choose_impl
    validate_impl

    detect_os
    detect_arch

    install_dependencies
    disable_firewall
    download_anytls
    generate_config
    create_service
    show_result
}

main "$@"
