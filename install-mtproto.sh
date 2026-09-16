#!/bin/sh
set -e
umask 077

CONFIG_DIR="/etc/mtproto-proxy"
NODE_INFO_FILE="/etc/mtproto-proxy/node-info.txt"
NODE_INFO_COPY="/root/mtproto-node-info.txt"
BUILD_DIR="/usr/local/src/MTProxy"
SERVICE_NAME="mtproxy"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/mtproxy.service"
OPENRC_SERVICE_FILE="/etc/init.d/mtproxy"
FALLBACK_SERVICE_FILE="/root/start-mtproto.sh"
PROXY_SECRET_FILE="$CONFIG_DIR/proxy-secret"
PROXY_SECRET_NEW="${PROXY_SECRET_FILE}.new.$$"
PROXY_SECRET_BACKUP="${PROXY_SECRET_FILE}.bak.$$"
PROXY_CONFIG_FILE="$CONFIG_DIR/proxy-multi.conf"
PROXY_CONFIG_NEW="${PROXY_CONFIG_FILE}.new.$$"
PROXY_CONFIG_BACKUP="${PROXY_CONFIG_FILE}.bak.$$"
MT_BINARY="/usr/local/bin/mtproto-proxy"
MT_BINARY_NEW="${MT_BINARY}.new.$$"
MT_BINARY_BACKUP="${MT_BINARY}.bak.$$"
MT_INSTALL_PENDING=0
HAD_MT_BINARY=0

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

current_saved_node_uses_port() {
  if [ -f "$NODE_INFO_FILE" ]; then
    grep -Eq '^端口：'"$1"'$' "$NODE_INFO_FILE"
    return $?
  fi
  if [ -f "$NODE_INFO_COPY" ]; then
    grep -Eq '^端口：'"$1"'$' "$NODE_INFO_COPY"
    return $?
  fi
  return 1
}

current_mtproto_is_running() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl is-active --quiet "$SERVICE_NAME"
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" status >/dev/null 2>&1
  else
    pgrep -f "/usr/local/bin/mtproto-proxy" >/dev/null 2>&1
  fi
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
      if ! current_saved_node_uses_port "$INPUT_PORT" || ! current_mtproto_is_running; then
        warn "TCP 端口已被占用：$INPUT_PORT"
        continue
      fi
    fi

    printf '%s' "$INPUT_PORT"
    return
  done
}

make_secret() {
  head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
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

detect_service_mode() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    SERVICE_MODE="systemd"
    CONTROL_FILE="$SYSTEMD_SERVICE_FILE"
  elif command -v rc-service >/dev/null 2>&1; then
    SERVICE_MODE="openrc"
    CONTROL_FILE="$OPENRC_SERVICE_FILE"
  else
    SERVICE_MODE="fallback"
    CONTROL_FILE="$FALLBACK_SERVICE_FILE"
  fi
  CONTROL_BACKUP="${CONTROL_FILE}.bak.$$"
}

start_configured_service() {
  case "$SERVICE_MODE" in
    systemd) write_systemd_service ;;
    openrc) write_openrc_service ;;
    fallback) write_fallback_launcher ;;
  esac
}

service_is_running() {
  case "$SERVICE_MODE" in
    systemd) systemctl is-active --quiet "$SERVICE_NAME" ;;
    openrc) rc-service "$SERVICE_NAME" status >/dev/null 2>&1 ;;
    fallback) pgrep -f "/usr/local/bin/mtproto-proxy" >/dev/null 2>&1 ;;
  esac
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

restart_previous_service() {
  case "$SERVICE_MODE" in
    systemd)
      systemctl daemon-reload &&
      systemctl enable --now "$SERVICE_NAME" &&
      systemctl restart "$SERVICE_NAME"
      ;;
    openrc)
      chmod 700 "$OPENRC_SERVICE_FILE"
      rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
      rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
      ;;
    fallback)
      chmod 700 "$FALLBACK_SERVICE_FILE"
      "$FALLBACK_SERVICE_FILE"
      ;;
  esac
}

activate_runtime() {
  detect_service_mode
  HAD_SECRET=0
  HAD_PROXY_CONFIG=0
  HAD_CONTROL=0
  rm -f "$PROXY_SECRET_BACKUP" "$PROXY_CONFIG_BACKUP" "$CONTROL_BACKUP"

  if [ -f "$PROXY_SECRET_FILE" ]; then
    cp -p "$PROXY_SECRET_FILE" "$PROXY_SECRET_BACKUP"
    HAD_SECRET=1
  fi
  if [ -f "$PROXY_CONFIG_FILE" ]; then
    cp -p "$PROXY_CONFIG_FILE" "$PROXY_CONFIG_BACKUP"
    HAD_PROXY_CONFIG=1
  fi
  if [ -f "$CONTROL_FILE" ]; then
    cp -p "$CONTROL_FILE" "$CONTROL_BACKUP"
    HAD_CONTROL=1
  fi

  stop_existing_mtproto
  mv -f "$PROXY_SECRET_NEW" "$PROXY_SECRET_FILE"
  mv -f "$PROXY_CONFIG_NEW" "$PROXY_CONFIG_FILE"

  if start_configured_service && wait_for_service_port; then
    finalize_mt_binary
    rm -f "$PROXY_SECRET_BACKUP" "$PROXY_CONFIG_BACKUP" "$CONTROL_BACKUP"
    return 0
  fi

  error "新配置启动失败，正在恢复旧 MTProto 服务"
  stop_existing_mtproto
  if [ "$HAD_CONTROL" -eq 0 ]; then
    case "$SERVICE_MODE" in
      systemd) systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true ;;
      openrc) rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true ;;
    esac
  fi
  rm -f "$PROXY_SECRET_FILE" "$PROXY_CONFIG_FILE" "$CONTROL_FILE"
  if [ "$HAD_SECRET" -eq 1 ]; then mv -f "$PROXY_SECRET_BACKUP" "$PROXY_SECRET_FILE"; fi
  if [ "$HAD_PROXY_CONFIG" -eq 1 ]; then mv -f "$PROXY_CONFIG_BACKUP" "$PROXY_CONFIG_FILE"; fi
  restore_mt_binary
  if [ "$HAD_CONTROL" -eq 1 ]; then
    mv -f "$CONTROL_BACKUP" "$CONTROL_FILE"
    if ! restart_previous_service; then
      warn "旧配置已恢复，但旧服务重启失败，请手动检查"
    fi
  elif [ "$SERVICE_MODE" = "systemd" ]; then
    systemctl daemon-reload
  fi
  rm -f "$PROXY_SECRET_BACKUP" "$PROXY_CONFIG_BACKUP" "$CONTROL_BACKUP"
  return 1
}

download_and_build_mtproto() {
  rm -rf "$BUILD_DIR"
  mkdir -p "$(dirname "$BUILD_DIR")"
  git clone --depth=1 https://github.com/TelegramMessenger/MTProxy "$BUILD_DIR"
  cd "$BUILD_DIR"
  make -j1
  if [ ! -x "objs/bin/mtproto-proxy" ]; then
    error "MTProxy 编译产物不存在或不可执行"
    return 1
  fi
  rm -f "$MT_BINARY_NEW" "$MT_BINARY_BACKUP"
  if [ -f "$MT_BINARY" ]; then
    cp -p "$MT_BINARY" "$MT_BINARY_BACKUP"
    HAD_MT_BINARY=1
  else
    HAD_MT_BINARY=0
  fi
  install -m 755 objs/bin/mtproto-proxy "$MT_BINARY_NEW"
  mv -f "$MT_BINARY_NEW" "$MT_BINARY"
  MT_INSTALL_PENDING=1
}

restore_mt_binary() {
  [ "$MT_INSTALL_PENDING" -eq 1 ] || return 0
  rm -f "$MT_BINARY"
  if [ "$HAD_MT_BINARY" -eq 1 ]; then
    mv -f "$MT_BINARY_BACKUP" "$MT_BINARY"
  else
    rm -f "$MT_BINARY_BACKUP"
  fi
  MT_INSTALL_PENDING=0
}

finalize_mt_binary() {
  rm -f "$MT_BINARY_BACKUP" "$MT_BINARY_NEW"
  MT_INSTALL_PENDING=0
}

cleanup_pending_mt() {
  if [ "$MT_INSTALL_PENDING" -eq 1 ]; then
    restore_mt_binary
  fi
}

prepare_runtime_files() {
  mkdir -p "$CONFIG_DIR"
  chmod 755 "$CONFIG_DIR"
  rm -f "$PROXY_SECRET_NEW" "$PROXY_CONFIG_NEW"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://core.telegram.org/getProxySecret -o "$PROXY_SECRET_NEW"
    curl -fsSL https://core.telegram.org/getProxyConfig -o "$PROXY_CONFIG_NEW"
  else
    wget -O "$PROXY_SECRET_NEW" https://core.telegram.org/getProxySecret
    wget -O "$PROXY_CONFIG_NEW" https://core.telegram.org/getProxyConfig
  fi
  if [ ! -s "$PROXY_SECRET_NEW" ] || [ ! -s "$PROXY_CONFIG_NEW" ]; then
    error "MTProto 运行数据下载不完整"
    return 1
  fi
  chmod 644 "$PROXY_SECRET_NEW" "$PROXY_CONFIG_NEW"
}

write_systemd_service() {
  SERVICE_TEMP="${SYSTEMD_SERVICE_FILE}.new.$$"
  rm -f "$SERVICE_TEMP"
  cat >"$SERVICE_TEMP" <<SERVICE
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

  chmod 600 "$SERVICE_TEMP"
  mv -f "$SERVICE_TEMP" "$SYSTEMD_SERVICE_FILE"

  systemctl daemon-reload &&
  systemctl enable --now "$SERVICE_NAME" &&
  systemctl restart "$SERVICE_NAME"
}

write_openrc_service() {
  SERVICE_TEMP="${OPENRC_SERVICE_FILE}.new.$$"
  rm -f "$SERVICE_TEMP"
  cat >"$SERVICE_TEMP" <<SERVICE
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

  chmod 700 "$SERVICE_TEMP"
  mv -f "$SERVICE_TEMP" "$OPENRC_SERVICE_FILE"
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
  rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start
}

write_fallback_launcher() {
  SERVICE_TEMP="${FALLBACK_SERVICE_FILE}.new.$$"
  rm -f "$SERVICE_TEMP"
  cat >"$SERVICE_TEMP" <<START
#!/bin/sh
pkill -f "/usr/local/bin/mtproto-proxy" 2>/dev/null || true
cd $CONFIG_DIR
nohup /usr/local/bin/mtproto-proxy -u nobody -p ${STATS_PORT} -H ${PORT} -S ${SECRET} --aes-pwd $CONFIG_DIR/proxy-secret $CONFIG_DIR/proxy-multi.conf -M 1 >/var/log/mtproto.log 2>&1 &
START
  chmod 700 "$SERVICE_TEMP"
  mv -f "$SERVICE_TEMP" "$FALLBACK_SERVICE_FILE"
  "$FALLBACK_SERVICE_FILE"
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
  printf '%b%s%b\n' "$GREEN" "$CLIENT_SECRET" "$RESET"
  printf '%b%s%b\n' "$CYAN" "服务端 Secret：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$SECRET" "$RESET"
  printf '%b%s%b\n' "$CYAN" "协议：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "MTProto Proxy" "$RESET"
  printf '%b%s%b\n' "$CYAN" "传输：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "TCP" "$RESET"
  printf '%b%s%b\n' "$CYAN" "模式：" "$RESET"
  printf '%b%s%b\n' "$GREEN" "dd 随机填充" "$RESET"
  echo
  printf '%b%s%b\n' "$BOLD$BLUE" "Telegram 链接" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${CLIENT_SECRET}" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${CLIENT_SECRET}" "$RESET"
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

客户端 Secret：$CLIENT_SECRET

服务端 Secret：$SECRET

协议：MTProto Proxy

传输：TCP

模式：dd 随机填充

Telegram 链接：
tg://proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${CLIENT_SECRET}
https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${CLIENT_SECRET}

===== 常用命令 =====
查看节点信息：/root/install-mtproto.sh info

查看服务状态：
systemctl status mtproxy --no-pager -l

查看监听端口：ss -tnlp | grep :${PORT}

配置文件：$CONFIG_DIR

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
    printf '%s\n' "  $0 info         查看已保存的 MTProto 节点信息"
    exit 1
    ;;
esac

require_root
if [ "${1:-}" != "install" ] && [ "${1:-}" != "--install" ]; then
  choose_action_if_installed
fi

install_deps

PUBLIC_IP="$(detect_ip)"
PORT="$(prompt_port)"
STATS_PORT="$(random_local_port)"
SECRET="$(make_secret)"
CLIENT_SECRET="dd${SECRET}"

trap cleanup_pending_mt EXIT
download_and_build_mtproto
prepare_runtime_files
activate_runtime

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
