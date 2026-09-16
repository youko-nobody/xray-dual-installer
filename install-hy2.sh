#!/bin/sh
set -e
umask 077

DEFAULT_PORT="8443"
SNI="bing.com"
MASQUERADE_URL="https://www.bing.com"
CONFIG_FILE="/etc/hysteria/config.yaml"
CONFIG_NEW="${CONFIG_FILE}.new.$$"
CONFIG_BACKUP="${CONFIG_FILE}.bak.$$"
CERT_DIR="/etc/hysteria/cert"
CERT_FILE="$CERT_DIR/server.crt"
CERT_NEW="${CERT_FILE}.new.$$"
CERT_BACKUP="${CERT_FILE}.bak.$$"
KEY_FILE="$CERT_DIR/server.key"
KEY_NEW="${KEY_FILE}.new.$$"
KEY_BACKUP="${KEY_FILE}.bak.$$"
NODE_INFO_FILE="/etc/hysteria/node-info.txt"
NODE_INFO_COPY="/root/hy2-node-info.txt"
HY2_BINARY="/usr/local/bin/hysteria"
HY2_BINARY_NEW="${HY2_BINARY}.new.$$"
HY2_BINARY_BACKUP="${HY2_BINARY}.bak.$$"
HY2_INSTALL_PENDING=0
HAD_HY2_BINARY=0

if [ -t 1 ]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  CYAN="$(printf '\033[36m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  CYAN=""
  BOLD=""
  RESET=""
fi

info() { printf '%b%s%b\n' "$CYAN" "$*" "$RESET"; }
success() { printf '%b%s%b\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$*" "$RESET" >&2; }
error() { printf '%b%s%b\n' "$RED" "$*" "$RESET" >&2; }
headline() { printf '%b%s%b\n' "$BOLD$BLUE" "$*" "$RESET"; }

require_root() {
  if [ "$(id -u)" != "0" ]; then
    error "请使用 root 用户运行此脚本"
    exit 1
  fi
}

fetch_url() {
  URL="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsL "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$URL"
  else
    return 1
  fi
}

detect_ip() {
  IP="$(fetch_url https://api.ipify.org || true)"
  [ -n "$IP" ] || IP="$(fetch_url https://ifconfig.me/ip || true)"
  [ -n "$IP" ] || IP="$(fetch_url https://ip.sb || true)"
  [ -n "$IP" ] || IP="$(fetch_url https://icanhazip.com || true)"
  IP="$(printf '%s' "$IP" | tr -d '\r\n')"
  [ -n "$IP" ] || {
    error "获取公网 IP 失败"
    exit 1
  }
  printf '%s' "$IP"
}

uri_host() {
  case "$1" in
    *:*) printf '[%s]' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget openssl ca-certificates bash procps iproute2
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget openssl ca-certificates bash procps iproute2
  else
    error "不支持的系统：未找到 apt-get 或 apk"
    exit 1
  fi
}

is_valid_port() {
  VALUE="$1"
  case "$VALUE" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$VALUE" -ge 1 ] && [ "$VALUE" -le 65535 ]
}

is_udp_port_in_use() {
  PORT_TO_CHECK="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnu 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  return 1
}

current_config_uses_port() {
  [ -f "$CONFIG_FILE" ] && grep -Eq '^listen:[[:space:]]*:'"$1"'$' "$CONFIG_FILE"
}

prompt_port() {
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bHY2 端口%b [默认: %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$DEFAULT_PORT" "$RESET" >/dev/tty
      read -r INPUT_PORT </dev/tty || INPUT_PORT=""
    else
      INPUT_PORT=""
    fi

    [ -n "$INPUT_PORT" ] || INPUT_PORT="$DEFAULT_PORT"

    if ! is_valid_port "$INPUT_PORT"; then
      warn "端口无效：$INPUT_PORT"
      continue
    fi

    if is_udp_port_in_use "$INPUT_PORT"; then
      if ! current_config_uses_port "$INPUT_PORT" || ! service_is_running; then
        warn "UDP 端口已被占用：$INPUT_PORT"
        continue
      fi
    fi

    printf '%s' "$INPUT_PORT"
    return
  done
}

make_password() {
  openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24
}

show_saved_node_info() {
  INFO_FILE="$1"
  awk \
    -v green="$GREEN" \
    -v yellow="$YELLOW" \
    -v blue="$BLUE" \
    -v cyan="$CYAN" \
    -v bold="$BOLD" \
    -v reset="$RESET" \
    '
      /^===== .* =====$/ { print bold blue $0 reset; next }
      /^(公网 IP|端口|密码|SNI|证书|配置文件|节点信息文件|查看节点信息|查看服务状态|查看监听端口)：/ { print cyan $0 reset; next }
      /^hy2:\/\// { print yellow $0 reset; next }
      /^\/.*$/ { print green $0 reset; next }
      { print }
    ' "$INFO_FILE"
}

show_node_info() {
  if [ -f "$NODE_INFO_FILE" ]; then
    show_saved_node_info "$NODE_INFO_FILE"
    return
  fi
  if [ -f "$NODE_INFO_COPY" ]; then
    show_saved_node_info "$NODE_INFO_COPY"
    return
  fi
  warn "未找到已保存的 HY2 节点信息"
  warn "请先运行安装脚本完成部署"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi

  info "检测到已保存的 HY2 节点信息"
  printf '%b1. 查看节点信息%b\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2. 重新安装 / 覆盖节点%b\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r ACTION </dev/tty || ACTION=""

  case "$ACTION" in
    ""|1)
      show_node_info
      exit 0
      ;;
    2)
      info "继续重新安装，将生成新的 HY2 节点信息"
      ;;
    *)
      error "无效选择，已取消"
      exit 1
      ;;
  esac
}

download_file() {
  DOWNLOAD_URL="$1"
  DOWNLOAD_PATH="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$DOWNLOAD_PATH" "$DOWNLOAD_URL"
  else
    wget -qO "$DOWNLOAD_PATH" "$DOWNLOAD_URL"
  fi
}

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}

detect_hysteria_asset() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) printf '%s' "hysteria-linux-amd64" ;;
    i386|i686) printf '%s' "hysteria-linux-386" ;;
    aarch64|arm64) printf '%s' "hysteria-linux-arm64" ;;
    armv7l) printf '%s' "hysteria-linux-arm" ;;
    riscv64) printf '%s' "hysteria-linux-riscv64" ;;
    *)
      error "不支持的系统架构：$ARCH"
      return 1
      ;;
  esac
}

cleanup_hy2_download() {
  rm -f "$HY2_TEMP_DIR/hysteria" "$HY2_TEMP_DIR/hashes.txt"
  rmdir "$HY2_TEMP_DIR" 2>/dev/null || true
}

install_hysteria_binary() {
  info "正在从官方 GitHub Release 安装 Hysteria2..."
  HY2_ASSET="$(detect_hysteria_asset)"
  HY2_TEMP_DIR="$(mktemp -d /tmp/hysteria-install.XXXXXX)"
  HY2_DOWNLOAD="$HY2_TEMP_DIR/hysteria"
  HY2_HASHES="$HY2_TEMP_DIR/hashes.txt"
  HY2_BASE_URL="https://github.com/apernet/hysteria/releases/latest/download"

  if ! download_file "$HY2_BASE_URL/$HY2_ASSET" "$HY2_DOWNLOAD" ||
     ! download_file "$HY2_BASE_URL/hashes.txt" "$HY2_HASHES"; then
    cleanup_hy2_download
    error "Hysteria2 下载失败"
    return 1
  fi

  EXPECTED_SHA256="$(awk -v name="build/$HY2_ASSET" '$2 == name {print $1; exit}' "$HY2_HASHES" | tr 'A-F' 'a-f')"
  ACTUAL_SHA256="$(file_sha256 "$HY2_DOWNLOAD" | tr 'A-F' 'a-f')"
  if ! printf '%s\n' "$EXPECTED_SHA256" | grep -Eq '^[0-9a-f]{64}$' ||
     [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
    cleanup_hy2_download
    error "Hysteria2 SHA-256 校验失败"
    return 1
  fi

  chmod 700 "$HY2_DOWNLOAD"
  if ! "$HY2_DOWNLOAD" version >/dev/null 2>&1; then
    cleanup_hy2_download
    error "Hysteria2 二进制无法执行"
    return 1
  fi

  rm -f "$HY2_BINARY_BACKUP" "$HY2_BINARY_NEW"
  if [ -f "$HY2_BINARY" ]; then
    cp -p "$HY2_BINARY" "$HY2_BINARY_BACKUP"
    HAD_HY2_BINARY=1
  else
    HAD_HY2_BINARY=0
  fi
  install -m 755 "$HY2_DOWNLOAD" "$HY2_BINARY_NEW"
  if ! "$HY2_BINARY_NEW" version >/dev/null 2>&1; then
    rm -f "$HY2_BINARY_NEW"
    cleanup_hy2_download
    error "安装后的 Hysteria2 二进制自检失败"
    return 1
  fi
  mv -f "$HY2_BINARY_NEW" "$HY2_BINARY"
  HY2_INSTALL_PENDING=1
  cleanup_hy2_download
}

restore_hy2_binary() {
  [ "$HY2_INSTALL_PENDING" -eq 1 ] || return 0
  rm -f "$HY2_BINARY"
  if [ "$HAD_HY2_BINARY" -eq 1 ]; then
    mv -f "$HY2_BINARY_BACKUP" "$HY2_BINARY"
  else
    rm -f "$HY2_BINARY_BACKUP"
  fi
  HY2_INSTALL_PENDING=0
}

finalize_hy2_binary() {
  rm -f "$HY2_BINARY_BACKUP" "$HY2_BINARY_NEW"
  HY2_INSTALL_PENDING=0
}

cleanup_pending_hy2() {
  if [ "$HY2_INSTALL_PENDING" -eq 1 ]; then
    restore_hy2_binary
  fi
}

stop_existing_hy2() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl stop hysteria-server.service >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service hysteria stop >/dev/null 2>&1 || true
  fi
  pkill -f "/usr/local/bin/hysteria server --config $CONFIG_FILE" 2>/dev/null || true
}

start_configured_service() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    write_systemd_service
  elif command -v rc-service >/dev/null 2>&1; then
    write_openrc_service
  else
    write_fallback_launcher
  fi
}

service_is_running() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl is-active --quiet hysteria-server.service
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service hysteria status >/dev/null 2>&1
  else
    pgrep -f "/usr/local/bin/hysteria server --config $CONFIG_FILE" >/dev/null 2>&1
  fi
}

wait_for_service_port() {
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 10 ]; do
    if service_is_running && is_udp_port_in_use "$PORT"; then
      return 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
  done
  return 1
}

activate_config() {
  HAD_CONFIG=0
  HAD_CERT=0
  HAD_KEY=0
  rm -f "$CONFIG_BACKUP" "$CERT_BACKUP" "$KEY_BACKUP"

  if [ -f "$CONFIG_FILE" ]; then
    cp -p "$CONFIG_FILE" "$CONFIG_BACKUP"
    HAD_CONFIG=1
  fi
  if [ -f "$CERT_FILE" ]; then
    cp -p "$CERT_FILE" "$CERT_BACKUP"
    HAD_CERT=1
  fi
  if [ -f "$KEY_FILE" ]; then
    cp -p "$KEY_FILE" "$KEY_BACKUP"
    HAD_KEY=1
  fi

  stop_existing_hy2
  mv -f "$CONFIG_NEW" "$CONFIG_FILE"
  mv -f "$CERT_NEW" "$CERT_FILE"
  mv -f "$KEY_NEW" "$KEY_FILE"

  if start_configured_service && wait_for_service_port; then
    finalize_hy2_binary
    rm -f "$CONFIG_BACKUP" "$CERT_BACKUP" "$KEY_BACKUP"
    return 0
  fi

  error "新配置启动失败，正在恢复旧配置和证书"
  stop_existing_hy2
  rm -f "$CONFIG_FILE" "$CERT_FILE" "$KEY_FILE"
  if [ "$HAD_CONFIG" -eq 1 ]; then mv -f "$CONFIG_BACKUP" "$CONFIG_FILE"; fi
  if [ "$HAD_CERT" -eq 1 ]; then mv -f "$CERT_BACKUP" "$CERT_FILE"; fi
  if [ "$HAD_KEY" -eq 1 ]; then mv -f "$KEY_BACKUP" "$KEY_FILE"; fi

  restore_hy2_binary
  if [ "$HAD_CONFIG" -eq 1 ]; then
    if ! start_configured_service; then
      warn "旧配置已恢复，但旧服务重启失败，请手动检查"
    fi
  fi
  rm -f "$CONFIG_BACKUP" "$CERT_BACKUP" "$KEY_BACKUP"
  return 1
}

write_systemd_service() {
  cat >/etc/systemd/system/hysteria-server.service <<SERVICE
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload &&
  systemctl enable --now hysteria-server.service &&
  systemctl restart hysteria-server.service
}

write_openrc_service() {
  cat >/etc/init.d/hysteria <<SERVICE
#!/sbin/openrc-run
name="hysteria"
description="Hysteria2 Server"

supervisor="supervise-daemon"
command="/usr/local/bin/hysteria"
command_args="server --config $CONFIG_FILE"

respawn_delay=5
respawn_max=0
respawn_period=60

depend() {
    need net
}
SERVICE

  chmod +x /etc/init.d/hysteria
  rc-update add hysteria default >/dev/null 2>&1 || true
  rc-service hysteria restart || rc-service hysteria start
}

write_fallback_launcher() {
  cat >/root/start-hy2.sh <<START
#!/bin/sh
pkill -f "/usr/local/bin/hysteria server --config $CONFIG_FILE" 2>/dev/null || true
nohup /usr/local/bin/hysteria server --config $CONFIG_FILE >/var/log/hysteria.log 2>&1 &
START
  chmod +x /root/start-hy2.sh
  /root/start-hy2.sh
}

show_status() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl status hysteria-server.service --no-pager -l || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service hysteria status || true
  fi

  ss -unlp | grep ":${PORT} " || true
}

show_final_summary() {
  headline "===== 最终节点信息 ====="
  echo
  printf '%b%s%b\n' "$CYAN" "公网 IP：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PUBLIC_IP" "$RESET"
  printf '%b%s%b\n' "$CYAN" "端口：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PORT" "$RESET"
  printf '%b%s%b\n' "$CYAN" "密码：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PASSWORD" "$RESET"
  printf '%b%s%b\n' "$CYAN" "SNI：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SNI" "$RESET"
  echo
  printf '%b%s%b\n' "$BOLD$BLUE" "HY2 链接" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "hy2://${PASSWORD}@${URI_HOST}:${PORT}?insecure=1&sni=${SNI}#HY2-${PUBLIC_IP}-${PORT}" "$RESET"
  echo
  printf '%b%s%b\n' "$CYAN" "节点信息文件：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== Hysteria2 节点信息 =====

公网 IP：$PUBLIC_IP

端口：$PORT

密码：$PASSWORD

SNI：$SNI

证书：自签证书，客户端需要开启 insecure / 跳过证书验证

链接：
hy2://${PASSWORD}@${URI_HOST}:${PORT}?insecure=1&sni=${SNI}#HY2-${PUBLIC_IP}-${PORT}

===== 常用命令 =====
查看节点信息：/root/install-hy2.sh info

查看服务状态：
systemctl status hysteria-server.service --no-pager -l

查看监听端口：ss -unlp | grep :${PORT}

配置文件：$CONFIG_FILE

节点信息文件：$NODE_INFO_FILE
$NODE_INFO_COPY
INFO

  chmod 600 "$NODE_INFO_FILE"
  cp "$NODE_INFO_FILE" "$NODE_INFO_COPY" 2>/dev/null || true
  chmod 600 "$NODE_INFO_COPY" 2>/dev/null || true
}

case "${1:-}" in
  info|show|view|--info|--show|--view)
    show_node_info
    exit 0
    ;;
  install|--install|"")
    ;;
  *)
    headline "用法："
    printf '%s\n' "  $0              安装或在已安装时显示菜单"
    printf '%s\n' "  $0 install      直接安装 / 重装"
    printf '%s\n' "  $0 info         查看已保存的 HY2 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps

PUBLIC_IP="$(detect_ip)"
URI_HOST="$(uri_host "$PUBLIC_IP")"
PORT="$(prompt_port)"
PASSWORD="$(make_password)"

trap cleanup_pending_hy2 EXIT
install_hysteria_binary

mkdir -p "$CERT_DIR" /etc/hysteria
rm -f "$CONFIG_NEW" "$CERT_NEW" "$KEY_NEW"
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$KEY_NEW" \
  -out "$CERT_NEW" \
  -days 36500 \
  -subj "/CN=${SNI}"

chmod 644 "$CERT_NEW"
chmod 600 "$KEY_NEW"

cat >"$CONFIG_NEW" <<CONFIG
listen: :${PORT}

tls:
  cert: $CERT_DIR/server.crt
  key: $CERT_DIR/server.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $MASQUERADE_URL
    rewriteHost: true
CONFIG

chmod 600 "$CONFIG_NEW"
activate_config

write_node_info

echo
headline "===== 服务状态 ====="
show_status
echo
success "HY2 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
