#!/bin/sh
set -e

CONFIG_DIR="/etc/mtproto-proxy"
NODE_INFO_FILE="/etc/mtproto-proxy/node-info.txt"
NODE_INFO_COPY="/root/mtproto-node-info.txt"
BUILD_DIR="/usr/local/src/MTProxy"
SERVICE_NAME="mtproxy"

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
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git make gcc g++ build-essential libssl-dev zlib1g-dev ca-certificates procps iproute2 net-tools
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget git make gcc g++ build-base openssl-dev zlib-dev linux-headers ca-certificates procps iproute2 net-tools
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

random_port() {
  while :; do
    PORT="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' | awk '{print 20000 + ($1 % 20000)}')"
    [ -n "$PORT" ] || PORT="$((24000 + ($$ % 10000)))"
    if ! is_tcp_port_in_use "$PORT"; then
      printf '%s' "$PORT"
      return
    fi
  done
}

random_local_port() {
  while :; do
    PORT="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' | awk '{print 10000 + ($1 % 4000)}')"
    [ -n "$PORT" ] || PORT="$((10000 + ($$ % 4000)))"
    if ! is_tcp_port_in_use "$PORT"; then
      printf '%s' "$PORT"
      return
    fi
  done
}

prompt_port() {
  RECOMMENDED_PORT="$(random_port)"
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bMTProto 端口%b [回车使用推荐值 %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$RECOMMENDED_PORT" "$RESET" >/dev/tty
      read -r INPUT_PORT </dev/tty || INPUT_PORT=""
    else
      INPUT_PORT=""
    fi

    [ -n "$INPUT_PORT" ] || INPUT_PORT="$RECOMMENDED_PORT"

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

make_secret() {
  printf 'dd%s' "$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
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
      /^(公网 IP|端口|Secret|协议|传输|模式|配置文件|节点信息文件|查看节点信息|查看服务状态|查看监听端口)：/ { print cyan $0 reset; next }
      /^(tg:\/\/proxy|https:\/\/t\.me\/proxy)/ { print yellow $0 reset; next }
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
  warn "未找到已保存的 MTProto 节点信息"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi

  info "检测到已保存的 MTProto 节点信息"
  printf '%b1. 查看节点信息%b\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2. 重新安装 / 覆盖节点%b\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r ACTION </dev/tty || ACTION=""

  case "$ACTION" in
    ""|1)
      show_node_info
      exit 0
      ;;
    2) ;;
    *)
      error "无效选择，已取消"
      exit 1
      ;;
  esac
}

stop_existing_mtproto() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
  fi
  pkill -f "/usr/local/bin/mtproto-proxy" 2>/dev/null || true
}

download_and_build_mtproto() {
  rm -rf "$BUILD_DIR"
  mkdir -p "$(dirname "$BUILD_DIR")"
  git clone --depth=1 https://github.com/TelegramMessenger/MTProxy "$BUILD_DIR"
  cd "$BUILD_DIR"
  make -j1
  install -m 755 objs/bin/mtproto-proxy /usr/local/bin/mtproto-proxy
}

prepare_runtime_files() {
  mkdir -p "$CONFIG_DIR"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://core.telegram.org/getProxySecret -o "$CONFIG_DIR/proxy-secret"
    curl -fsSL https://core.telegram.org/getProxyConfig -o "$CONFIG_DIR/proxy-multi.conf"
  else
    wget -O "$CONFIG_DIR/proxy-secret" https://core.telegram.org/getProxySecret
    wget -O "$CONFIG_DIR/proxy-multi.conf" https://core.telegram.org/getProxyConfig
  fi
}

write_systemd_service() {
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<SERVICE
[Unit]
Description=Telegram MTProto Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=$CONFIG_DIR
ExecStart=/usr/local/bin/mtproto-proxy -u nobody -p ${STATS_PORT} -H ${PORT} -S ${SECRET} --aes-pwd $CONFIG_DIR/proxy-secret $CONFIG_DIR/proxy-multi.conf -M 1
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
name="mtproxy"
description="Telegram MTProto Proxy"

supervisor="supervise-daemon"
command="/usr/local/bin/mtproto-proxy"
command_args="-u nobody -p ${STATS_PORT} -H ${PORT} -S ${SECRET} --aes-pwd $CONFIG_DIR/proxy-secret $CONFIG_DIR/proxy-multi.conf -M 1"
directory="$CONFIG_DIR"

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
  cat >/root/start-mtproto.sh <<START
#!/bin/sh
pkill -f "/usr/local/bin/mtproto-proxy" 2>/dev/null || true
cd $CONFIG_DIR
nohup /usr/local/bin/mtproto-proxy -u nobody -p ${STATS_PORT} -H ${PORT} -S ${SECRET} --aes-pwd $CONFIG_DIR/proxy-secret $CONFIG_DIR/proxy-multi.conf -M 1 >/var/log/mtproto.log 2>&1 &
START
  chmod +x /root/start-mtproto.sh
  /root/start-mtproto.sh
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
  printf '%b%s%b\n' "$CYAN" "Secret：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SECRET" "$RESET"
  printf '%b%s%b\n' "$CYAN" "协议：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "MTProto Proxy" "$RESET"
  printf '%b%s%b\n' "$CYAN" "传输：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "TCP" "$RESET"
  printf '%b%s%b\n' "$CYAN" "模式：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "dd 随机填充" "$RESET"
  echo
  printf '%b%s%b\n' "$BOLD$BLUE" "Telegram 链接" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}" "$RESET"
  echo
  printf '%b%s%b\n' "$CYAN" "节点信息文件：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

write_node_info() {
  cat >"$NODE_INFO_FILE" <<INFO
===== MTProto 节点信息 =====

公网 IP：$PUBLIC_IP

端口：$PORT

Secret：$SECRET

协议：MTProto Proxy

传输：TCP

模式：dd 随机填充

Telegram 链接：
tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}
https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}

===== 常用命令 =====
查看节点信息：/root/install-mtproto.sh info

查看服务状态：
systemctl status mtproxy --no-pager -l

查看监听端口：ss -tnlp | grep :${PORT}

配置文件：$CONFIG_DIR

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
    printf '%s\n' "  $0 info         查看已保存的 MTProto 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps
stop_existing_mtproto

PUBLIC_IP="$(detect_ip)"
PORT="$(prompt_port)"
STATS_PORT="$(random_local_port)"
SECRET="$(make_secret)"

download_and_build_mtproto
prepare_runtime_files

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
success "MTProto 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
