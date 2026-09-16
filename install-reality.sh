#!/bin/sh
set -e
umask 077

DEFAULT_PORT="443"
SNI="www.sony.com"
SERVICE_NAME="xray-reality"
CONFIG_FILE="/usr/local/etc/xray/reality-config.json"
CONFIG_NEW="${CONFIG_FILE%.json}.new.$$.json"
CONFIG_BACKUP="${CONFIG_FILE}.bak.$$"
NODE_INFO_FILE="/usr/local/etc/xray/reality-node-info.txt"
NODE_INFO_COPY="/root/reality-node-info.txt"
ACCESS_LOG="/var/log/xray-reality-access.log"
ERROR_LOG="/var/log/xray-reality-error.log"
PID_HINT="run -config $CONFIG_FILE"
XRAY_BINARY="/usr/local/bin/xray"
XRAY_BINARY_NEW="${XRAY_BINARY}.new.$$"
XRAY_BINARY_BACKUP="${XRAY_BINARY}.bak.$$"
XRAY_INSTALL_PENDING=0
HAD_XRAY_BINARY=0

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
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip openssl ca-certificates procps iproute2 net-tools
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget unzip openssl ca-certificates procps iproute2 net-tools
  else
    error "不支持的系统：未找到 apt-get 或 apk"
    exit 1
  fi
}

detect_xray_zip() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) printf '%s' "Xray-linux-64.zip" ;;
    aarch64|arm64) printf '%s' "Xray-linux-arm64-v8a.zip" ;;
    armv7l) printf '%s' "Xray-linux-arm32-v7a.zip" ;;
    *)
      error "不支持的系统架构：$ARCH"
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

cleanup_xray_download() {
  rm -f "$XRAY_TEMP_DIR/xray.zip" "$XRAY_TEMP_DIR/xray.zip.dgst"
  rm -f "$XRAY_TEMP_DIR/extract/xray"
  rmdir "$XRAY_TEMP_DIR/extract" 2>/dev/null || true
  rmdir "$XRAY_TEMP_DIR" 2>/dev/null || true
}

install_xray_binary() {
  XRAY_TEMP_DIR="$(mktemp -d /tmp/xray-install.XXXXXX)"
  XRAY_ARCHIVE="$XRAY_TEMP_DIR/xray.zip"
  XRAY_DIGEST="$XRAY_TEMP_DIR/xray.zip.dgst"
  XRAY_BASE_URL="https://github.com/XTLS/Xray-core/releases/latest/download"

  if ! download_file "$XRAY_BASE_URL/$XRAY_ZIP" "$XRAY_ARCHIVE" ||
     ! download_file "$XRAY_BASE_URL/${XRAY_ZIP}.dgst" "$XRAY_DIGEST"; then
    cleanup_xray_download
    error "Xray 下载失败"
    return 1
  fi

  EXPECTED_SHA256="$(awk -F'= *' '/^SHA2-256=/ {print $2; exit}' "$XRAY_DIGEST" | tr 'A-F' 'a-f')"
  ACTUAL_SHA256="$(file_sha256 "$XRAY_ARCHIVE" | tr 'A-F' 'a-f')"
  if ! printf '%s\n' "$EXPECTED_SHA256" | grep -Eq '^[0-9a-f]{64}$' ||
     [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
    cleanup_xray_download
    error "Xray SHA-256 校验失败"
    return 1
  fi

  if ! unzip -tq "$XRAY_ARCHIVE" >/dev/null 2>&1; then
    cleanup_xray_download
    error "Xray 压缩包校验失败"
    return 1
  fi
  mkdir -p "$XRAY_TEMP_DIR/extract"
  if ! unzip -oq "$XRAY_ARCHIVE" xray -d "$XRAY_TEMP_DIR/extract" ||
     ! "$XRAY_TEMP_DIR/extract/xray" version >/dev/null 2>&1; then
    cleanup_xray_download
    error "Xray 二进制无法执行"
    return 1
  fi

  rm -f "$XRAY_BINARY_BACKUP" "$XRAY_BINARY_NEW"
  if [ -f "$XRAY_BINARY" ]; then
    cp -p "$XRAY_BINARY" "$XRAY_BINARY_BACKUP"
    HAD_XRAY_BINARY=1
  else
    HAD_XRAY_BINARY=0
  fi
  install -m 755 "$XRAY_TEMP_DIR/extract/xray" "$XRAY_BINARY_NEW"
  if ! "$XRAY_BINARY_NEW" version >/dev/null 2>&1; then
    rm -f "$XRAY_BINARY_NEW"
    cleanup_xray_download
    error "安装后的 Xray 二进制自检失败"
    return 1
  fi
  mv -f "$XRAY_BINARY_NEW" "$XRAY_BINARY"
  XRAY_INSTALL_PENDING=1
  cleanup_xray_download
}

restore_xray_binary() {
  [ "$XRAY_INSTALL_PENDING" -eq 1 ] || return 0
  rm -f "$XRAY_BINARY"
  if [ "$HAD_XRAY_BINARY" -eq 1 ]; then
    mv -f "$XRAY_BINARY_BACKUP" "$XRAY_BINARY"
  else
    rm -f "$XRAY_BINARY_BACKUP"
  fi
  XRAY_INSTALL_PENDING=0
}

finalize_xray_binary() {
  rm -f "$XRAY_BINARY_BACKUP" "$XRAY_BINARY_NEW"
  XRAY_INSTALL_PENDING=0
}

cleanup_pending_xray() {
  if [ "$XRAY_INSTALL_PENDING" -eq 1 ]; then
    restore_xray_binary
  fi
}

is_valid_port() {
  VALUE="$1"
  case "$VALUE" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$VALUE" -ge 1 ] && [ "$VALUE" -le 65535 ]
}

is_tcp_port_in_use() {
  PORT_TO_CHECK="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  return 1
}

current_config_uses_port() {
  [ -f "$CONFIG_FILE" ] &&
    grep -Eq '"port"[[:space:]]*:[[:space:]]*'"$1"'([,[:space:]]|$)' "$CONFIG_FILE"
}

prompt_port() {
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bReality 端口%b [默认: %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$DEFAULT_PORT" "$RESET" >/dev/tty
      read -r INPUT_PORT </dev/tty || INPUT_PORT=""
    else
      INPUT_PORT=""
    fi
    [ -n "$INPUT_PORT" ] || INPUT_PORT="$DEFAULT_PORT"
    if ! is_valid_port "$INPUT_PORT"; then
      warn "端口无效：$INPUT_PORT"
      continue
    fi
    if is_tcp_port_in_use "$INPUT_PORT"; then
      if ! current_config_uses_port "$INPUT_PORT" || ! service_is_running; then
        warn "TCP 端口已被占用：$INPUT_PORT"
        continue
      fi
    fi
    printf '%s' "$INPUT_PORT"
    return
  done
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
      /^(公网 IP|端口|SNI|UUID|PublicKey|Short ID|配置文件|节点信息文件|服务名|查看节点信息|查看服务状态|查看监听端口)：/ { print cyan $0 reset; next }
      /^vless:\/\// { print yellow $0 reset; next }
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
  warn "未找到已保存的 Reality 节点信息"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi
  info "检测到已保存的 Reality 节点信息"
  printf '%b1. 查看节点信息%b\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2. 重新安装 / 覆盖节点%b\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r ACTION </dev/tty || ACTION=""
  case "$ACTION" in
    ""|1) show_node_info; exit 0 ;;
    2) ;;
    *) error "无效选择，已取消"; exit 1 ;;
  esac
}

stop_existing_service() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
  fi
  pkill -f "$PID_HINT" 2>/dev/null || true
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
    systemctl is-active --quiet "$SERVICE_NAME"
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" status >/dev/null 2>&1
  else
    pgrep -f "$PID_HINT" >/dev/null 2>&1
  fi
}

wait_for_service_port() {
  ATTEMPT=0
  while [ "$ATTEMPT" -lt 10 ]; do
    if service_is_running && is_tcp_port_in_use "$PORT"; then
      return 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
  done
  return 1
}

activate_config() {
  HAD_CONFIG=0
  rm -f "$CONFIG_BACKUP"
  if [ -f "$CONFIG_FILE" ]; then
    cp -p "$CONFIG_FILE" "$CONFIG_BACKUP"
    HAD_CONFIG=1
  fi

  stop_existing_service
  mv -f "$CONFIG_NEW" "$CONFIG_FILE"

  if start_configured_service && wait_for_service_port; then
    finalize_xray_binary
    rm -f "$CONFIG_BACKUP"
    return 0
  fi

  error "新配置启动失败，正在恢复旧配置"
  stop_existing_service
  rm -f "$CONFIG_FILE"
  if [ "$HAD_CONFIG" -eq 1 ]; then
    mv -f "$CONFIG_BACKUP" "$CONFIG_FILE"
    restore_xray_binary
    if ! start_configured_service; then
      warn "旧配置已恢复，但旧服务重启失败，请手动检查"
    fi
  else
    restore_xray_binary
    rm -f "$CONFIG_BACKUP"
  fi
  return 1
}

write_systemd_service() {
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<SERVICE
[Unit]
Description=Xray Reality Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload &&
  systemctl enable --now "$SERVICE_NAME" &&
  systemctl restart "$SERVICE_NAME"
}

write_openrc_service() {
  cat >/etc/init.d/${SERVICE_NAME} <<SERVICE
#!/sbin/openrc-run
name="$SERVICE_NAME"
description="Xray Reality Service"
supervisor="supervise-daemon"
command="/usr/local/bin/xray"
command_args="run -config $CONFIG_FILE"
respawn_delay=5
respawn_max=0
respawn_period=60
depend() {
    need net
}
SERVICE
  chmod +x /etc/init.d/${SERVICE_NAME}
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

write_fallback_launcher() {
  cat >/root/start-${SERVICE_NAME}.sh <<START
#!/bin/sh
pkill -f "$PID_HINT" 2>/dev/null || true
nohup /usr/local/bin/xray run -config $CONFIG_FILE >/var/log/${SERVICE_NAME}.log 2>&1 &
START
  chmod +x /root/start-${SERVICE_NAME}.sh
  /root/start-${SERVICE_NAME}.sh
}

show_status() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl status "$SERVICE_NAME" --no-pager -l || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" status || true
  fi
  ss -tnlp | grep ":${PORT} " || netstat -tunlp | grep ":${PORT} " || true
}

show_final_summary() {
  headline "===== 最终节点信息 ====="
  echo
  printf '%b%s%b\n' "$CYAN" "公网 IP：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PUBLIC_IP" "$RESET"
  printf '%b%s%b\n' "$CYAN" "端口：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PORT" "$RESET"
  printf '%b%s%b\n' "$CYAN" "SNI：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SNI" "$RESET"
  printf '%b%s%b\n' "$CYAN" "UUID：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$UUID" "$RESET"
  printf '%b%s%b\n' "$CYAN" "PublicKey：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PUBLIC_KEY" "$RESET"
  printf '%b%s%b\n' "$CYAN" "Short ID：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SHORT_ID" "$RESET"
  printf '%b%s%b\n' "$CYAN" "服务名：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SERVICE_NAME" "$RESET"
  echo
  printf '%b%s%b\n' "$BOLD$BLUE" "Reality 链接" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "vless://${UUID}@${URI_HOST}:${PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${PORT}" "$RESET"
  echo
  printf '%b%s%b\n' "$CYAN" "节点信息文件：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== Reality 节点信息 =====

公网 IP：$PUBLIC_IP

端口：$PORT

SNI：$SNI

UUID：$UUID

PublicKey：$PUBLIC_KEY

Short ID：$SHORT_ID

服务名：$SERVICE_NAME

链接：vless://${UUID}@${URI_HOST}:${PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${PORT}

===== 常用命令 =====
查看节点信息：/root/install-reality.sh info

查看服务状态：
systemctl status $SERVICE_NAME --no-pager -l

查看监听端口：ss -tnlp | grep :${PORT}

配置文件：$CONFIG_FILE

节点信息文件：$NODE_INFO_FILE
$NODE_INFO_COPY
INFO
  chmod 600 "$NODE_INFO_FILE"
  cp "$NODE_INFO_FILE" "$NODE_INFO_COPY" 2>/dev/null || true
  chmod 600 "$NODE_INFO_COPY" 2>/dev/null || true
}

case "${1:-}" in
  info|show|view|--info|--show|--view) show_node_info; exit 0 ;;
  install|--install|"") ;;
  *)
    headline "用法："
    printf '%s\n' "  $0              安装或在已安装时显示菜单"
    printf '%s\n' "  $0 install      直接安装 / 重装"
    printf '%s\n' "  $0 info         查看已保存的 Reality 节点信息"
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
case "$PUBLIC_IP" in
  *:*) LISTEN_ADDRESS="::" ;;
  *) LISTEN_ADDRESS="0.0.0.0" ;;
esac
PORT="$(prompt_port)"
XRAY_ZIP="$(detect_xray_zip)"
trap cleanup_pending_xray EXIT
install_xray_binary

mkdir -p /usr/local/etc/xray
touch "$ACCESS_LOG" "$ERROR_LOG"

UUID="$(/usr/local/bin/xray uuid)"
KEYS="$(/usr/local/bin/xray x25519)"
PRIVATE_KEY="$(echo "$KEYS" | awk -F': ' '/PrivateKey/ {print $2}')"
PUBLIC_KEY="$(echo "$KEYS" | awk -F': ' '/Password \(PublicKey\)/ {print $2}')"
SHORT_ID="$(openssl rand -hex 8)"

rm -f "$CONFIG_NEW"
cat >"$CONFIG_NEW" <<CONFIG
{
  "log": {
    "access": "$ACCESS_LOG",
    "error": "$ERROR_LOG",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "$LISTEN_ADDRESS",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
CONFIG

chmod 600 "$CONFIG_NEW"
/usr/local/bin/xray run -test -config "$CONFIG_NEW"
activate_config

write_node_info

echo
headline "===== 服务状态 ====="
show_status
echo
success "Reality 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
