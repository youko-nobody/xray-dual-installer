#!/bin/sh
set -e

SNI="www.sony.com"
WS_PATH="/ws"
NODE_INFO_FILE="/usr/local/etc/xray/node-info.txt"
NODE_INFO_COPY="/root/xray-node-info.txt"
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

info() {
  printf '%b%s%b\n' "$CYAN" "$*" "$RESET"
}

success() {
  printf '%b%s%b\n' "$GREEN" "$*" "$RESET"
}

warn() {
  printf '%b%s%b\n' "$YELLOW" "$*" "$RESET" >&2
}

error() {
  printf '%b%s%b\n' "$RED" "$*" "$RESET" >&2
}

headline() {
  printf '%b%s%b\n' "$BOLD$BLUE" "$*" "$RESET"
}

label() {
  printf '%b%s%b' "$CYAN" "$1" "$RESET"
}

value() {
  printf '%b%s%b\n' "$GREEN" "$1" "$RESET"
}

print_node_info_colored() {
  headline "===== Xray 双节点信息 ====="
  echo
  label "公网 IP："
  value "$PUBLIC_IP"
  echo

  printf '%b%s%b\n' "$BOLD$GREEN" "===== Reality 节点 =====" "$RESET"
  label "端口："
  value "$REALITY_PORT"
  label "SNI："
  value "$SNI"
  label "UUID："
  value "$REALITY_UUID"
  label "PublicKey："
  value "$PUBLIC_KEY"
  label "Short ID："
  value "$SHORT_ID"
  label "链接："
  echo
  printf '%b%s%b\n' "$YELLOW" "vless://${REALITY_UUID}@${PUBLIC_IP}:${REALITY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${REALITY_PORT}" "$RESET"
  echo

  printf '%b%s%b\n' "$BOLD$GREEN" "===== WS 节点 =====" "$RESET"
  label "端口："
  value "$WS_PORT"
  label "路径："
  value "$WS_PATH"
  label "UUID："
  value "$WS_UUID"
  label "链接："
  echo
  printf '%b%s%b\n' "$YELLOW" "vless://${WS_UUID}@${PUBLIC_IP}:${WS_PORT}?type=ws&security=none&path=%2Fws#WS-${PUBLIC_IP}-${WS_PORT}" "$RESET"
  echo

  headline "===== 常用命令 ====="
  label "查看节点信息："
  echo
  printf '%b%s%b\n' "$GREEN" "/root/install-xray-dual-auto.sh info" "$RESET"
  echo
  label "配置文件："
  echo
  printf '%b%s%b\n' "$GREEN" "/usr/local/etc/xray/config.json" "$RESET"
  echo
  label "节点信息文件："
  echo
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

print_saved_node_info_colored() {
  INFO_FILE="$1"
  awk \
    -v red="$RED" \
    -v green="$GREEN" \
    -v yellow="$YELLOW" \
    -v blue="$BLUE" \
    -v cyan="$CYAN" \
    -v bold="$BOLD" \
    -v reset="$RESET" \
    '
      /^===== .* =====$/ { print bold blue $0 reset; next }
      /^(公网 IP|端口|SNI|UUID|PublicKey|Short ID|路径|查看节点信息|配置文件|节点信息文件)：/ { print cyan $0 reset; next }
      /^vless:\/\// { print yellow $0 reset; next }
      /^\/.*$/ { print green $0 reset; next }
      { print }
    ' "$INFO_FILE"
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    error "请使用 root 用户运行此脚本"
    exit 1
  fi
}

show_node_info() {
  if [ -f "$NODE_INFO_FILE" ]; then
    print_saved_node_info_colored "$NODE_INFO_FILE"
    return
  fi

  if [ -f "$NODE_INFO_COPY" ]; then
    print_saved_node_info_colored "$NODE_INFO_COPY"
    return
  fi

  warn "未找到已保存的节点信息。"
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

  info "检测到已保存的节点信息。"
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
      info "继续重新安装，将生成新的节点信息。"
      ;;
    *)
      error "无效选择，已取消。"
      exit 1
      ;;
  esac
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip openssl ca-certificates net-tools procps
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget unzip openssl ca-certificates net-tools procps
  else
    error "不支持的系统：未找到 apt-get 或 apk"
    exit 1
  fi
}

fetch_url() {
  URL="$1"
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$URL"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsL "$URL"
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

is_port_in_use() {
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

random_port() {
  while :; do
    if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
      RANDOM_NUM="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')"
      CANDIDATE="$((20000 + (RANDOM_NUM % 30000)))"
    else
      CANDIDATE="$(awk 'BEGIN{srand(); print int(20000 + rand() * 30000)}')"
    fi

    if ! is_port_in_use "$CANDIDATE"; then
      printf '%s' "$CANDIDATE"
      return
    fi
  done
}

is_valid_port() {
  VALUE="$1"
  case "$VALUE" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  if [ "$VALUE" -lt 1 ] || [ "$VALUE" -gt 65535 ]; then
    return 1
  fi

  return 0
}

prompt_port() {
  LABEL="$1"
  DEFAULT_VALUE="$2"
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%b%s%b [默认: %b%s%b]: ' "$CYAN" "$LABEL" "$RESET" "$GREEN" "$DEFAULT_VALUE" "$RESET" >/dev/tty
      read -r INPUT_VALUE </dev/tty || INPUT_VALUE=""
    else
      INPUT_VALUE=""
    fi

    if [ -z "$INPUT_VALUE" ]; then
      printf '%s' "$DEFAULT_VALUE"
      return
    fi

    if is_valid_port "$INPUT_VALUE"; then
      if is_port_in_use "$INPUT_VALUE"; then
        warn "端口已被占用：$INPUT_VALUE"
        continue
      fi
      printf '%s' "$INPUT_VALUE"
      return
    fi

    warn "端口无效：$INPUT_VALUE"
  done
}

write_systemd_service() {
  cat >/etc/systemd/system/xray.service <<'SERVICE'
[Unit]
Description=Xray Core
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now xray
}

write_openrc_service() {
  cat >/etc/init.d/xray <<'SERVICE'
#!/sbin/openrc-run
name="xray"
description="Xray Core"

supervisor="supervise-daemon"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"

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
  cat >/root/start-xray.sh <<'START'
#!/bin/sh
pkill -f "/usr/local/bin/xray run -config /usr/local/etc/xray/config.json" 2>/dev/null || true
nohup /usr/local/bin/xray run -config /usr/local/etc/xray/config.json >/var/log/xray.log 2>&1 &
START

  chmod +x /root/start-xray.sh
  /root/start-xray.sh
}

show_status() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl status xray --no-pager || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service xray status || true
  fi

  ss -tnlp | grep -E ":${REALITY_PORT}|:${WS_PORT}" || \
    netstat -tunlp | grep -E ":${REALITY_PORT}|:${WS_PORT}" || true
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
    printf '%b\n' "  $0              安装或在已安装时显示菜单"
    printf '%b\n' "  $0 install      直接安装 / 重装"
    printf '%b\n' "  $0 info         查看已保存的节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps

PUBLIC_IP="$(detect_ip)"
XRAY_ZIP="$(detect_xray_zip)"
DEFAULT_REALITY_PORT="$(random_port)"
DEFAULT_WS_PORT="$(random_port)"

while [ "$DEFAULT_WS_PORT" = "$DEFAULT_REALITY_PORT" ]; do
  DEFAULT_WS_PORT="$(random_port)"
done

info "检测到公网 IP：$PUBLIC_IP"
REALITY_PORT="$(prompt_port "Reality 端口" "$DEFAULT_REALITY_PORT")"
WS_PORT="$(prompt_port "WS 端口" "$DEFAULT_WS_PORT")"

if ! is_valid_port "$REALITY_PORT"; then
  error "Reality 端口无效：$REALITY_PORT"
  exit 1
fi

if ! is_valid_port "$WS_PORT"; then
  error "WS 端口无效：$WS_PORT"
  exit 1
fi

if is_port_in_use "$REALITY_PORT"; then
  error "Reality 端口已被占用：$REALITY_PORT"
  exit 1
fi

if is_port_in_use "$WS_PORT"; then
  error "WS 端口已被占用：$WS_PORT"
  exit 1
fi

if [ "$REALITY_PORT" = "$WS_PORT" ]; then
  error "Reality 端口和 WS 端口不能相同"
  exit 1
fi

cd /root
rm -f xray.zip xray
wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ZIP}"
unzip -o xray.zip
install -m 755 xray /usr/local/bin/xray
mkdir -p /usr/local/etc/xray
touch /var/log/xray-access.log /var/log/xray-error.log

REALITY_UUID="$(/usr/local/bin/xray uuid)"
WS_UUID="$(/usr/local/bin/xray uuid)"
KEYS="$(/usr/local/bin/xray x25519)"
PRIVATE_KEY="$(echo "$KEYS" | awk -F': ' '/PrivateKey/ {print $2}')"
PUBLIC_KEY="$(echo "$KEYS" | awk -F': ' '/Password \(PublicKey\)/ {print $2}')"
SHORT_ID="$(openssl rand -hex 8)"

cat >/usr/local/etc/xray/config.json <<CONFIG
{
  "log": {
    "access": "/var/log/xray-access.log",
    "error": "/var/log/xray-error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${REALITY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${REALITY_UUID}",
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
    },
    {
      "listen": "0.0.0.0",
      "port": ${WS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${WS_UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
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

/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json

if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
  write_systemd_service
elif command -v rc-service >/dev/null 2>&1; then
  write_openrc_service
else
  write_fallback_launcher
fi

cat >"$NODE_INFO_FILE" <<INFO
===== Xray 双节点信息 =====

公网 IP：
$PUBLIC_IP

===== Reality 节点 =====
端口：$REALITY_PORT
SNI：$SNI
UUID：$REALITY_UUID
PublicKey：$PUBLIC_KEY
Short ID：$SHORT_ID
链接：
vless://${REALITY_UUID}@${PUBLIC_IP}:${REALITY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${REALITY_PORT}

===== WS 节点 =====
端口：$WS_PORT
路径：$WS_PATH
UUID：$WS_UUID
链接：
vless://${WS_UUID}@${PUBLIC_IP}:${WS_PORT}?type=ws&security=none&path=%2Fws#WS-${PUBLIC_IP}-${WS_PORT}

===== 常用命令 =====
查看节点信息：
/root/install-xray-dual-auto.sh info

配置文件：
/usr/local/etc/xray/config.json

节点信息文件：
$NODE_INFO_FILE
$NODE_INFO_COPY
INFO

cp "$NODE_INFO_FILE" "$NODE_INFO_COPY" 2>/dev/null || true

echo
print_node_info_colored
echo
success "节点信息已保存到："
printf '%b\n' "$GREEN$NODE_INFO_FILE$RESET"
printf '%b\n' "$GREEN$NODE_INFO_COPY$RESET"
echo
headline "===== 服务状态 ====="
show_status
