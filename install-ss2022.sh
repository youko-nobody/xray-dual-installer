#!/bin/sh
set -e

MIN_SING_BOX_MAJOR="1"
MIN_SING_BOX_MINOR="12"
SERVICE_NAME="sing-box-ss2022"
BINARY_FILE="/usr/local/bin/sing-box-ss2022"
CONFIG_DIR="/etc/sing-box-ss2022"
CONFIG_FILE="$CONFIG_DIR/config.json"
NODE_INFO_FILE="$CONFIG_DIR/node-info.txt"
NODE_INFO_COPY="/root/ss2022-node-info.txt"
FALLBACK_LOG="/var/log/sing-box-ss2022.log"
PID_HINT="$BINARY_FILE run -c $CONFIG_FILE"

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

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR" 2>/dev/null || true
  fi
  rm -f "$BINARY_FILE.new" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

require_root() {
  if [ "$(id -u)" != "0" ]; then
    error "请使用 root 用户运行此脚本"
    exit 1
  fi
}

fetch_url() {
  URL="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$URL"
  else
    return 1
  fi
}

download_file() {
  URL="$1"
  OUTPUT="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$OUTPUT" "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$OUTPUT" "$URL"
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
  case "$IP" in
    ''|*[!0-9A-Fa-f:.]*)
      error "获取公网 IP 失败"
      exit 1
      ;;
  esac
  printf '%s' "$IP"
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar openssl ca-certificates jq coreutils procps iproute2 net-tools
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget tar openssl ca-certificates jq coreutils procps iproute2 net-tools
  else
    error "不支持的系统：未找到 apt-get 或 apk"
    exit 1
  fi
}

detect_sing_box_arch() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) printf '%s' "amd64" ;;
    aarch64|arm64) printf '%s' "arm64" ;;
    armv7l|armv7) printf '%s' "armv7" ;;
    *)
      error "不支持的系统架构：$ARCH"
      exit 1
      ;;
  esac
}

version_is_supported() {
  VERSION_TO_CHECK="$1"
  VERSION_MAJOR="$(printf '%s' "$VERSION_TO_CHECK" | awk -F. '{print $1}')"
  VERSION_MINOR="$(printf '%s' "$VERSION_TO_CHECK" | awk -F. '{print $2}')"
  case "$VERSION_MAJOR:$VERSION_MINOR" in
    *[!0-9:]*|:|*:) return 1 ;;
  esac
  [ "$VERSION_MAJOR" -gt "$MIN_SING_BOX_MAJOR" ] || {
    [ "$VERSION_MAJOR" -eq "$MIN_SING_BOX_MAJOR" ] && [ "$VERSION_MINOR" -ge "$MIN_SING_BOX_MINOR" ]
  }
}

install_sing_box() {
  info "正在获取 sing-box 最新稳定版本..."
  if ! RELEASE_JSON="$(fetch_url https://api.github.com/repos/SagerNet/sing-box/releases/latest)"; then
    error "无法读取 sing-box 最新版本信息"
    exit 1
  fi

  VERSION_TAG="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty')"
  RELEASE_ID="$(printf '%s' "$RELEASE_JSON" | jq -r '.id // empty')"
  VERSION="${VERSION_TAG#v}"
  if [ -z "$VERSION" ] || [ -z "$RELEASE_ID" ] || ! version_is_supported "$VERSION"; then
    error "sing-box 版本无效或低于 ${MIN_SING_BOX_MAJOR}.${MIN_SING_BOX_MINOR}：${VERSION:-未知}"
    exit 1
  fi

  SING_BOX_ARCH="$(detect_sing_box_arch)"
  ARCHIVE_NAME="sing-box-${VERSION}-linux-${SING_BOX_ARCH}.tar.gz"
  DOWNLOAD_URL=""
  EXPECTED_DIGEST=""
  ASSET_PAGE="1"
  while [ "$ASSET_PAGE" -le 5 ]; do
    if ! ASSETS_JSON="$(fetch_url "https://api.github.com/repos/SagerNet/sing-box/releases/${RELEASE_ID}/assets?per_page=100&page=${ASSET_PAGE}")"; then
      error "无法读取 sing-box 发布包列表"
      exit 1
    fi
    DOWNLOAD_URL="$(printf '%s' "$ASSETS_JSON" | jq -r --arg name "$ARCHIVE_NAME" '.[] | select(.name == $name) | .browser_download_url' | head -n 1)"
    EXPECTED_DIGEST="$(printf '%s' "$ASSETS_JSON" | jq -r --arg name "$ARCHIVE_NAME" '.[] | select(.name == $name) | (.digest // empty)' | head -n 1)"
    [ -n "$DOWNLOAD_URL" ] && break
    ASSET_COUNT="$(printf '%s' "$ASSETS_JSON" | jq 'length')"
    [ "$ASSET_COUNT" -ge 100 ] || break
    ASSET_PAGE="$((ASSET_PAGE + 1))"
  done

  if [ -z "$DOWNLOAD_URL" ]; then
    error "未找到适用于当前架构的发布包：$ARCHIVE_NAME"
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  ARCHIVE_FILE="$TMP_DIR/$ARCHIVE_NAME"
  info "正在下载：$ARCHIVE_NAME"
  download_file "$DOWNLOAD_URL" "$ARCHIVE_FILE"

  case "$EXPECTED_DIGEST" in
    sha256:*)
      EXPECTED_SHA256="${EXPECTED_DIGEST#sha256:}"
      ACTUAL_SHA256="$(sha256sum "$ARCHIVE_FILE" | awk '{print $1}')"
      if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
        error "sing-box 发布包 SHA-256 校验失败"
        exit 1
      fi
      success "sing-box 发布包 SHA-256 校验通过"
      ;;
    *)
      warn "GitHub Release 未提供 SHA-256 摘要，将继续校验压缩包和程序版本"
      ;;
  esac

  tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"
  EXTRACTED_BINARY="$TMP_DIR/sing-box-${VERSION}-linux-${SING_BOX_ARCH}/sing-box"
  if [ ! -f "$EXTRACTED_BINARY" ]; then
    error "发布包中未找到 sing-box 程序"
    exit 1
  fi

  install -m 755 "$EXTRACTED_BINARY" "$BINARY_FILE.new"
  INSTALLED_VERSION="$($BINARY_FILE.new version 2>/dev/null | awk '/sing-box version/ {print $3; exit}')"
  if [ "$INSTALLED_VERSION" != "$VERSION" ]; then
    error "sing-box 程序版本校验失败：期望 $VERSION，得到 ${INSTALLED_VERSION:-未知}"
    exit 1
  fi
  mv -f "$BINARY_FILE.new" "$BINARY_FILE"
  SING_BOX_VERSION="$VERSION"
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

is_udp_port_in_use() {
  PORT_TO_CHECK="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnu 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnu 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT_TO_CHECK$"
    return $?
  fi
  return 1
}

is_port_in_use() {
  is_tcp_port_in_use "$1" || is_udp_port_in_use "$1"
}

random_port() {
  while :; do
    RANDOM_PORT="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' | awk '{print 20000 + ($1 % 20000)}')"
    [ -n "$RANDOM_PORT" ] || RANDOM_PORT="$((20000 + ($$ % 20000)))"
    if ! is_port_in_use "$RANDOM_PORT"; then
      printf '%s' "$RANDOM_PORT"
      return
    fi
  done
}

service_is_running() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
  fi
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    return $?
  fi
  pgrep -f "$PID_HINT" >/dev/null 2>&1
}

read_owned_port() {
  if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE" 2>/dev/null || true
  fi
}

prompt_port() {
  OWNED_PORT="$(read_owned_port)"
  if is_valid_port "$OWNED_PORT" && service_is_running; then
    RECOMMENDED_PORT="$OWNED_PORT"
  else
    RECOMMENDED_PORT="$(random_port)"
  fi

  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bSS2022 端口%b [回车使用推荐值 %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$RECOMMENDED_PORT" "$RESET" >/dev/tty
      read -r INPUT_PORT </dev/tty || INPUT_PORT=""
    else
      INPUT_PORT=""
    fi
    [ -n "$INPUT_PORT" ] || INPUT_PORT="$RECOMMENDED_PORT"
    if ! is_valid_port "$INPUT_PORT"; then
      warn "端口无效：$INPUT_PORT"
      continue
    fi
    if is_port_in_use "$INPUT_PORT"; then
      if [ "$INPUT_PORT" = "$OWNED_PORT" ] && service_is_running; then
        printf '%s' "$INPUT_PORT"
        return
      fi
      warn "TCP 或 UDP 端口已被占用：$INPUT_PORT"
      continue
    fi
    printf '%s' "$INPUT_PORT"
    return
  done
}

prompt_method() {
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    printf '%s' "2022-blake3-aes-128-gcm"
    return
  fi

  headline "===== SS2022 加密方式 =====" >/dev/tty
  printf '%b1.%b 2022-blake3-aes-128-gcm（默认，兼容性最好）\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2.%b 2022-blake3-aes-256-gcm\n' "$CYAN" "$RESET" >/dev/tty
  printf '%b3.%b 2022-blake3-chacha20-poly1305（Surge 不支持）\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r METHOD_CHOICE </dev/tty || METHOD_CHOICE=""
  case "$METHOD_CHOICE" in
    ""|1) printf '%s' "2022-blake3-aes-128-gcm" ;;
    2) printf '%s' "2022-blake3-aes-256-gcm" ;;
    3) printf '%s' "2022-blake3-chacha20-poly1305" ;;
    *) error "无效选择"; exit 1 ;;
  esac
}

method_key_bytes() {
  case "$1" in
    2022-blake3-aes-128-gcm) printf '%s' "16" ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) printf '%s' "32" ;;
    *) return 1 ;;
  esac
}

make_key() {
  openssl rand -base64 "$1" | tr -d '\r\n'
}

validate_key() {
  KEY_TO_CHECK="$1"
  EXPECTED_BYTES="$2"
  case "$KEY_TO_CHECK" in
    ''|*[!A-Za-z0-9+/=]*) return 1 ;;
  esac
  CANONICAL_KEY="$(printf '%s' "$KEY_TO_CHECK" | openssl base64 -d -A 2>/dev/null | openssl base64 -A 2>/dev/null || true)"
  [ "$CANONICAL_KEY" = "$KEY_TO_CHECK" ] || return 1
  KEY_HEX="$(printf '%s' "$KEY_TO_CHECK" | openssl base64 -d -A 2>/dev/null | od -An -tx1 | tr -d ' \r\n')"
  [ "${#KEY_HEX}" -eq "$((EXPECTED_BYTES * 2))" ]
}

uri_host() {
  case "$1" in
    *:*) printf '[%s]' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

base64url_encode() {
  printf '%s' "$1" | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='
}

build_share_link() {
  URI_SERVER="$(uri_host "$PUBLIC_IP")"
  USER_INFO="$(base64url_encode "$METHOD:$PASSWORD")"
  printf '%s' "ss://${USER_INFO}@${URI_SERVER}:${PORT}#SS2022-${PORT}"
}

build_surge_block() {
  case "$METHOD" in
    2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm)
      printf '%s\n' "[Proxy]"
      printf '%s' "SS2022-${PORT} = ss, $PUBLIC_IP, $PORT, encrypt-method=$METHOD, password=$PASSWORD, udp-relay=true"
      ;;
    *)
      printf '%s' "当前加密方式不受 Surge 支持，请使用 sing-box、Mihomo 等兼容客户端。"
      ;;
  esac
}

write_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  case "$PUBLIC_IP" in
    *:*) LISTEN_ADDRESS="::" ;;
    *) LISTEN_ADDRESS="0.0.0.0" ;;
  esac

  cat >"$CONFIG_FILE.new" <<CONFIG
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss2022-in",
      "listen": "${LISTEN_ADDRESS}",
      "listen_port": ${PORT},
      "method": "${METHOD}",
      "password": "${PASSWORD}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
CONFIG

  chmod 600 "$CONFIG_FILE.new"
  jq empty "$CONFIG_FILE.new"
  "$BINARY_FILE" check -c "$CONFIG_FILE.new"
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

write_systemd_service() {
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<SERVICE
[Unit]
Description=sing-box Shadowsocks 2022 Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
UMask=0077
ExecStart=$BINARY_FILE run -c $CONFIG_FILE
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
}

write_openrc_service() {
  cat >/etc/init.d/${SERVICE_NAME} <<SERVICE
#!/sbin/openrc-run
name="$SERVICE_NAME"
description="sing-box Shadowsocks 2022 Service"
supervisor="supervise-daemon"
command="$BINARY_FILE"
command_args="run -c $CONFIG_FILE"
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
nohup $BINARY_FILE run -c $CONFIG_FILE >$FALLBACK_LOG 2>&1 &
START
  chmod +x /root/start-${SERVICE_NAME}.sh
  /root/start-${SERVICE_NAME}.sh
}

start_service() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    write_systemd_service
  elif command -v rc-service >/dev/null 2>&1; then
    write_openrc_service
  else
    write_fallback_launcher
  fi
}

wait_for_service() {
  WAIT_COUNT="0"
  while [ "$WAIT_COUNT" -lt 15 ]; do
    if service_is_running && is_tcp_port_in_use "$PORT" && is_udp_port_in_use "$PORT"; then
      return 0
    fi
    WAIT_COUNT="$((WAIT_COUNT + 1))"
    sleep 1
  done
  return 1
}

show_status() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl status "$SERVICE_NAME" --no-pager -l || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" status || true
  fi
  ss -lntp 2>/dev/null | grep ":${PORT} " || netstat -lntp 2>/dev/null | grep ":${PORT} " || true
  ss -lnup 2>/dev/null | grep ":${PORT} " || netstat -lnup 2>/dev/null | grep ":${PORT} " || true
}

write_node_info() {
  SHARE_LINK="$(build_share_link)"
  SURGE_BLOCK="$(build_surge_block)"
  cat >"$NODE_INFO_FILE" <<INFO
===== Shadowsocks 2022 节点信息 =====

服务器地址：$PUBLIC_IP

端口：$PORT

加密方式：$METHOD

密钥：$PASSWORD

传输：TCP + UDP

sing-box 版本：$SING_BOX_VERSION

服务名：$SERVICE_NAME

链接：$SHARE_LINK

Surge 配置：
$SURGE_BLOCK

Mihomo 配置：
- name: SS2022-$PORT
  type: ss
  server: "$PUBLIC_IP"
  port: $PORT
  cipher: $METHOD
  password: "$PASSWORD"
  udp: true

===== 常用命令 =====
查看节点信息：/root/install-ss2022.sh info

查看服务状态：
systemctl status $SERVICE_NAME --no-pager -l

查看 TCP 监听：ss -lntp | grep :${PORT}

查看 UDP 监听：ss -lnup | grep :${PORT}

检查配置：$BINARY_FILE check -c $CONFIG_FILE

配置文件：$CONFIG_FILE

节点信息文件：$NODE_INFO_FILE
$NODE_INFO_COPY
INFO
  chmod 600 "$NODE_INFO_FILE"
  cp "$NODE_INFO_FILE" "$NODE_INFO_COPY"
  chmod 600 "$NODE_INFO_COPY"
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
      /^(服务器地址|端口|加密方式|密钥|传输|sing-box 版本|服务名|Surge 配置|Mihomo 配置|配置文件|节点信息文件|查看节点信息|查看服务状态|查看 TCP 监听|查看 UDP 监听|检查配置)：/ { print cyan $0 reset; next }
      /^链接：ss:\/\// { print yellow $0 reset; next }
      /^\[Proxy\]$/ { print bold green $0 reset; next }
      /^SS2022-.* = ss, / { print yellow $0 reset; next }
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
  warn "未找到已保存的 SS2022 节点信息"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi
  info "检测到已保存的 SS2022 节点信息"
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

show_final_summary() {
  SHARE_LINK="$(build_share_link)"
  SURGE_BLOCK="$(build_surge_block)"
  headline "===== 最终节点信息 ====="
  echo
  printf '%b服务器地址：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PUBLIC_IP" "$RESET"
  printf '%b端口：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PORT" "$RESET"
  printf '%b加密方式：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$METHOD" "$RESET"
  printf '%b密钥：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PASSWORD" "$RESET"
  printf '%b服务名：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$SERVICE_NAME" "$RESET"
  echo
  printf '%bSS2022 链接%b\n' "$BOLD$BLUE" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "$SHARE_LINK" "$RESET"
  echo
  printf '%bSurge 配置%b\n' "$BOLD$BLUE" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "$SURGE_BLOCK" "$RESET"
  echo
  printf '%b节点信息文件：%b\n' "$CYAN" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
}

case "${1:-}" in
  info|show|view|--info|--show|--view) show_node_info; exit 0 ;;
  install|--install|"") ;;
  *)
    headline "用法："
    printf '%s\n' "  $0              安装或在已安装时显示菜单"
    printf '%s\n' "  $0 install      直接安装 / 重装"
    printf '%s\n' "  $0 info         查看已保存的 SS2022 节点信息"
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
METHOD="$(prompt_method)"
KEY_BYTES="$(method_key_bytes "$METHOD")"
PASSWORD="$(make_key "$KEY_BYTES")"
if ! validate_key "$PASSWORD" "$KEY_BYTES"; then
  error "生成的 SS2022 密钥格式或长度无效"
  exit 1
fi

install_sing_box
write_config

ROLLBACK_CONFIG=""
if [ -f "$CONFIG_FILE" ]; then
  ROLLBACK_CONFIG="$CONFIG_FILE.rollback"
  cp "$CONFIG_FILE" "$ROLLBACK_CONFIG"
fi

stop_existing_service
mv -f "$CONFIG_FILE.new" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

if ! start_service || ! wait_for_service; then
  error "SS2022 服务启动失败，或未同时监听 TCP 和 UDP"
  show_status
  if [ -n "$ROLLBACK_CONFIG" ] && [ -f "$ROLLBACK_CONFIG" ]; then
    warn "正在恢复旧配置并尝试重新启动原服务"
    mv -f "$ROLLBACK_CONFIG" "$CONFIG_FILE"
    start_service >/dev/null 2>&1 || true
  fi
  exit 1
fi

rm -f "$ROLLBACK_CONFIG"
write_node_info

echo
headline "===== 服务状态 ====="
show_status
echo
success "SS2022 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
