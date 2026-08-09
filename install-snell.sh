#!/bin/sh
set -e

DEFAULT_PORT="8666"
DEFAULT_MODE="default"
SNELL_VERSION="v6.0.0rc2"
CONFIG_DIR="/etc/snell"
CONFIG_FILE="/etc/snell/snell-server.conf"
NODE_INFO_FILE="/etc/snell/node-info.txt"
NODE_INFO_COPY="/root/snell-node-info.txt"
SERVICE_NAME="snell"

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

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip openssl ca-certificates procps iproute2 net-tools
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget unzip openssl ca-certificates procps iproute2 net-tools gcompat libstdc++
  else
    error "不支持的系统：未找到 apt-get 或 apk"
    exit 1
  fi
}

detect_snell_zip() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) printf '%s' "snell-server-${SNELL_VERSION}-linux-amd64.zip" ;;
    i386|i686) printf '%s' "snell-server-${SNELL_VERSION}-linux-i386.zip" ;;
    aarch64|arm64) printf '%s' "snell-server-${SNELL_VERSION}-linux-aarch64.zip" ;;
    armv7l) printf '%s' "snell-server-v5.0.1-linux-armv7l.zip" ;;
    *)
      error "不支持的系统架构：$ARCH"
      exit 1
      ;;
  esac
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

prompt_port() {
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bSnell 端口%b [默认: %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$DEFAULT_PORT" "$RESET" >/dev/tty
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
      warn "TCP 端口已被占用：$INPUT_PORT"
      continue
    fi

    printf '%s' "$INPUT_PORT"
    return
  done
}

prompt_mode() {
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    printf '%s' "$DEFAULT_MODE"
    return
  fi

  printf '\n' >/dev/tty
  printf '%b1.%b default     推荐，启用混淆和加密\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2.%b unshaped   关闭混淆，只保留加密，性能更高\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b3.%b unsafe-raw 明文转发，只适合内网或其他安全隧道内\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 Snell 模式 [默认: 1]: ' >/dev/tty
  read -r MODE_CHOICE </dev/tty || MODE_CHOICE=""

  case "$MODE_CHOICE" in
    ""|1) printf '%s' "default" ;;
    2) printf '%s' "unshaped" ;;
    3) printf '%s' "unsafe-raw" ;;
    *)
      warn "无效选择，已使用默认模式 default"
      printf '%s' "default"
      ;;
  esac
}

make_psk() {
  openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32
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
      /^(公网 IP|端口|PSK|版本|模式|配置片段|配置文件|节点信息文件|查看节点信息|查看服务状态|查看监听端口)：/ { print cyan $0 reset; next }
      /^snell = / { print yellow $0 reset; next }
      /^\[Proxy\]$/ { print bold green $0 reset; next }
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
  warn "未找到已保存的 Snell 节点信息"
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

  info "检测到已保存的 Snell 节点信息"
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
      info "继续重新安装，将生成新的 Snell 节点信息"
      ;;
    *)
      error "无效选择，已取消"
      exit 1
      ;;
  esac
}

download_snell() {
  ZIP_NAME="$(detect_snell_zip)"
  URL="https://dl.nssurge.com/snell/${ZIP_NAME}"
  cd /root
  rm -f snell.zip snell-server
  if command -v wget >/dev/null 2>&1; then
    wget -O snell.zip "$URL"
  else
    curl -fsSL -o snell.zip "$URL"
  fi
  unzip -o snell.zip
  install -m 755 snell-server /usr/local/bin/snell-server
}

stop_existing_snell() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
  fi
  pkill -f "/usr/local/bin/snell-server -c $CONFIG_FILE" 2>/dev/null || true
}

write_systemd_service() {
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<SERVICE
[Unit]
Description=Snell Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snell-server -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

write_openrc_service() {
  cat >/etc/init.d/${SERVICE_NAME} <<SERVICE
#!/sbin/openrc-run
name="snell"
description="Snell Server"

supervisor="supervise-daemon"
command="/usr/local/bin/snell-server"
command_args="-c $CONFIG_FILE"

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
  cat >/root/start-snell.sh <<START
#!/bin/sh
pkill -f "/usr/local/bin/snell-server -c $CONFIG_FILE" 2>/dev/null || true
nohup /usr/local/bin/snell-server -c $CONFIG_FILE >/var/log/snell.log 2>&1 &
START
  chmod +x /root/start-snell.sh
  /root/start-snell.sh
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
  printf '%b%s%b\n' "$CYAN" "PSK：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$PSK" "$RESET"
  printf '%b%s%b\n' "$CYAN" "版本：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "6" "$RESET"
  printf '%b%s%b\n' "$CYAN" "模式：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$MODE" "$RESET"
  echo
  printf '%b%s%b\n' "$BOLD$BLUE" "[Proxy]" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "snell = $PUBLIC_IP, $PORT, psk=$PSK, version=6, reuse=true" "$RESET"
  echo
  printf '%b%s%b\n' "$CYAN" "节点信息文件：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== Snell v6 节点信息 =====

公网 IP：$PUBLIC_IP

端口：$PORT

PSK：$PSK

版本：6

模式：$MODE

配置片段：
[Proxy]
snell = $PUBLIC_IP, $PORT, psk=$PSK, version=6, reuse=true

说明：Snell 主要用于 Surge，其他常见代理客户端通常不支持。

===== 常用命令 =====
查看节点信息：/root/install-snell.sh info

查看服务状态：
systemctl status snell --no-pager -l

查看监听端口：ss -tnlp | grep :${PORT}

配置文件：$CONFIG_FILE

节点信息文件：$NODE_INFO_FILE
$NODE_INFO_COPY
INFO

  cp "$NODE_INFO_FILE" "$NODE_INFO_COPY" 2>/dev/null || true
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
    printf '%s\n' "  $0 info         查看已保存的 Snell 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps
stop_existing_snell

PUBLIC_IP="$(detect_ip)"
PORT="$(prompt_port)"
MODE="$(prompt_mode)"
MODE="$(printf '%s' "$MODE" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
case "$MODE" in
  default|unshaped|unsafe-raw) ;;
  *)
    warn "检测到异常 mode 值，已自动回退到 default"
    MODE="default"
    ;;
esac
PSK="$(make_psk)"

download_snell

mkdir -p "$CONFIG_DIR"

cat >"$CONFIG_FILE" <<CONFIG
[snell-server]
listen = 0.0.0.0:${PORT},[::]:${PORT}
psk = ${PSK}
ipv6 = true
dns-ip-preference = default
mode = ${MODE}
CONFIG

if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  write_systemd_service
elif command -v rc-service >/dev/null 2>&1; then
  write_openrc_service
else
  write_fallback_launcher
fi

write_node_info

echo
headline "===== 服务状态 ====="
show_status
echo
success "Snell 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
