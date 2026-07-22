#!/bin/sh
set -e

DEFAULT_PORT="443"
SNI="www.sony.com"
CONFIG_FILE="/usr/local/etc/xray/config.json"
NODE_INFO_FILE="/usr/local/etc/xray/reality-node-info.txt"
NODE_INFO_COPY="/root/reality-node-info.txt"

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
      warn "TCP 端口已被占用：$INPUT_PORT"
      continue
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
      /^(公网 IP|端口|SNI|UUID|PublicKey|Short ID|配置文件|节点信息文件|查看节点信息|查看服务状态|查看监听端口)：/ { print cyan $0 reset; next }
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
  warn "未找到已保存的单 Reality 节点信息。"
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

  info "检测到已保存的单 Reality 节点信息。"
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
      info "继续重新安装，将生成新的单 Reality 节点信息。"
      ;;
    *)
      error "无效选择，已取消。"
      exit 1
      ;;
  esac
}

stop_existing_xray() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl stop xray >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service xray stop >/dev/null 2>&1 || true
  fi
  pkill -f "/usr/local/bin/xray run -config $CONFIG_FILE" 2>/dev/null || true
}

write_systemd_service() {
  cat >/etc/systemd/system/xray.service <<SERVICE
[Unit]
Description=Xray Core
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

  systemctl daemon-reload
  systemctl enable --now xray
  systemctl restart xray
}

write_openrc_service() {
  cat >/etc/init.d/xray <<SERVICE
#!/sbin/openrc-run
name="xray"
description="Xray Core"

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

  chmod +x /etc/init.d/xray
  rc-update add xray default >/dev/null 2>&1 || true
  rc-service xray restart || rc-service xray start
}

write_fallback_launcher() {
  cat >/root/start-xray.sh <<START
#!/bin/sh
pkill -f "/usr/local/bin/xray run -config $CONFIG_FILE" 2>/dev/null || true
nohup /usr/local/bin/xray run -config $CONFIG_FILE >/var/log/xray.log 2>&1 &
START
  chmod +x /root/start-xray.sh
  /root/start-xray.sh
}

show_status() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl status xray --no-pager -l || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service xray status || true
  fi

  ss -tnlp | grep ":${PORT} " || netstat -tunlp | grep ":${PORT} " || true
}

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== 单 Reality 节点信息 =====

公网 IP：
$PUBLIC_IP

端口：
$PORT

SNI：
$SNI

UUID：
$UUID

PublicKey：
$PUBLIC_KEY

Short ID：
$SHORT_ID

链接：
vless://${UUID}@${PUBLIC_IP}:${PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${PORT}

===== 常用命令 =====
查看节点信息：
/root/install-reality.sh info

查看服务状态：
systemctl status xray --no-pager -l

查看监听端口：
ss -tnlp | grep :${PORT}

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
    printf '%s\n' "  $0 info         查看已保存的单 Reality 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps
stop_existing_xray

PUBLIC_IP="$(detect_ip)"
PORT="$(prompt_port)"
XRAY_ZIP="$(detect_xray_zip)"

cd /root
rm -f xray.zip xray
wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ZIP}"
unzip -o xray.zip
install -m 755 xray /usr/local/bin/xray

mkdir -p /usr/local/etc/xray
touch /var/log/xray-access.log /var/log/xray-error.log

UUID="$(/usr/local/bin/xray uuid)"
KEYS="$(/usr/local/bin/xray x25519)"
PRIVATE_KEY="$(echo "$KEYS" | awk -F': ' '/PrivateKey/ {print $2}')"
PUBLIC_KEY="$(echo "$KEYS" | awk -F': ' '/Password \(PublicKey\)/ {print $2}')"
SHORT_ID="$(openssl rand -hex 8)"

cat >"$CONFIG_FILE" <<CONFIG
{
  "log": {
    "access": "/var/log/xray-access.log",
    "error": "/var/log/xray-error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
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
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
CONFIG

/usr/local/bin/xray run -test -config "$CONFIG_FILE"

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
success "单 Reality 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
headline "===== 服务状态 ====="
show_status
