#!/bin/sh
set -e

DEFAULT_PORT="8443"
SNI="bing.com"
MASQUERADE_URL="https://www.bing.com"
CONFIG_FILE="/etc/hysteria/config.yaml"
CERT_DIR="/etc/hysteria/cert"
NODE_INFO_FILE="/etc/hysteria/node-info.txt"
NODE_INFO_COPY="/root/hy2-node-info.txt"

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
label() { printf '%b%s%b' "$CYAN" "$1" "$RESET"; }
value() { printf '%b%s%b\n' "$GREEN" "$1" "$RESET"; }

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
    ss -unlp 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  return 1
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
      warn "UDP 端口已被占用：$INPUT_PORT"
      continue
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
  warn "未找到已保存的 HY2 节点信息。"
  warn "请先运行安装脚本完成部署。"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi

  info "检测到已保存的 HY2 节点信息。"
  printf '%b1. 查看节点信息%b\n' "$GREEN" "$RESET"
  printf '%b2. 重新安装 / 覆盖节点%b\n' "$YELLOW" "$RESET"
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r ACTION </dev/tty || ACTION=""

  case "$ACTION" in
    ""|1)
      show_node_info
      exit 0
      ;;
    2)
      info "继续重新安装，将生成新的 HY2 节点信息。"
      ;;
    *)
      error "无效选择，已取消。"
      exit 1
      ;;
  esac
}

install_hysteria_binary() {
  info "正在安装 Hysteria2..."
  curl -fsSL https://get.hy2.sh/ | bash
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

  systemctl daemon-reload
  systemctl enable --now hysteria-server.service
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

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== Hysteria2 节点信息 =====

公网 IP：
$PUBLIC_IP

端口：
$PORT

密码：
$PASSWORD

SNI：
$SNI

证书：
自签证书，客户端需要开启 insecure / 跳过证书验证。

链接：
hy2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#HY2-${PUBLIC_IP}-${PORT}

===== 常用命令 =====
查看节点信息：
/root/install-hy2.sh info

查看服务状态：
systemctl status hysteria-server.service --no-pager -l

查看监听端口：
ss -unlp | grep :${PORT}

配置文件：
$CONFIG_FILE

节点信息文件：
$NODE_INFO_FILE
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
    printf '%s\n' "  $0 info         查看已保存的 HY2 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps
stop_existing_hy2

PUBLIC_IP="$(detect_ip)"
PORT="$(prompt_port)"
PASSWORD="$(make_password)"

install_hysteria_binary

mkdir -p "$CERT_DIR" /etc/hysteria
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.crt" \
  -days 36500 \
  -subj "/CN=${SNI}"

chmod 644 "$CERT_DIR/server.crt" "$CERT_DIR/server.key"

cat >"$CONFIG_FILE" <<CONFIG
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

if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  write_systemd_service
elif command -v rc-service >/dev/null 2>&1; then
  write_openrc_service
else
  write_fallback_launcher
fi

write_node_info

echo
show_saved_node_info "$NODE_INFO_FILE"
echo
success "HY2 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
headline "===== 服务状态 ====="
show_status
