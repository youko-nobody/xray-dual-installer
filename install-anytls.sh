#!/bin/sh
set -e

DEFAULT_PORT="443"
DEFAULT_SNI="bing.com"
MIN_SING_BOX_MAJOR="1"
MIN_SING_BOX_MINOR="14"
SERVICE_NAME="sing-box-anytls"
BINARY_FILE="/usr/local/bin/sing-box-anytls"
CONFIG_DIR="/etc/sing-box-anytls"
CONFIG_FILE="$CONFIG_DIR/config.json"
CERT_DIR="$CONFIG_DIR/cert"
ACME_DIR="$CONFIG_DIR/acme"
NODE_INFO_FILE="$CONFIG_DIR/node-info.txt"
NODE_INFO_COPY="/root/anytls-node-info.txt"
FALLBACK_LOG="/var/log/sing-box-anytls.log"
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
CERT_BACKUP_DIR=""
CERT_FILES_CHANGED="0"
cleanup() {
  if [ "$CERT_FILES_CHANGED" = "1" ]; then
    restore_certificate_backup
  fi
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR"
  fi
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
    rm -f "$BINARY_FILE.new"
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

random_port() {
  while :; do
    RANDOM_PORT="$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' | awk '{print 20000 + ($1 % 20000)}')"
    [ -n "$RANDOM_PORT" ] || RANDOM_PORT="$((20000 + ($$ % 20000)))"
    if ! is_tcp_port_in_use "$RANDOM_PORT"; then
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
  if is_tcp_port_in_use "$DEFAULT_PORT" && [ "$OWNED_PORT" != "$DEFAULT_PORT" ]; then
    RECOMMENDED_PORT="$(random_port)"
  else
    RECOMMENDED_PORT="$DEFAULT_PORT"
  fi

  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bAnyTLS 端口%b [回车使用推荐值 %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$RECOMMENDED_PORT" "$RESET" >/dev/tty
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
      if [ "$INPUT_PORT" = "$OWNED_PORT" ] && service_is_running; then
        printf '%s' "$INPUT_PORT"
        return
      fi
      warn "TCP 端口已被占用：$INPUT_PORT"
      continue
    fi
    printf '%s' "$INPUT_PORT"
    return
  done
}

make_password() {
  openssl rand -hex 16
}

is_valid_password() {
  VALUE="$1"
  case "$VALUE" in
    ''|*[!A-Za-z0-9._~-]*) return 1 ;;
  esac
  return 0
}

prompt_password() {
  RECOMMENDED_PASSWORD="$(make_password)"
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      printf '%bAnyTLS 密码%b [回车使用随机值 %b%s%b]: ' "$CYAN" "$RESET" "$GREEN" "$RECOMMENDED_PASSWORD" "$RESET" >/dev/tty
      read -r INPUT_PASSWORD </dev/tty || INPUT_PASSWORD=""
    else
      INPUT_PASSWORD=""
    fi
    [ -n "$INPUT_PASSWORD" ] || INPUT_PASSWORD="$RECOMMENDED_PASSWORD"
    if ! is_valid_password "$INPUT_PASSWORD"; then
      warn "密码只能包含英文字母、数字以及 . _ ~ -"
      continue
    fi
    printf '%s' "$INPUT_PASSWORD"
    return
  done
}

is_valid_hostname() {
  VALUE="$1"
  case "$VALUE" in
    ''|*[!A-Za-z0-9.-]*|.*|*.|*..*) return 1 ;;
  esac
  return 0
}

prompt_hostname() {
  TITLE="$1"
  DEFAULT_VALUE="${2:-}"
  while :; do
    if [ -t 0 ] && [ -r /dev/tty ]; then
      if [ -n "$DEFAULT_VALUE" ]; then
        printf '%b%s%b [默认: %b%s%b]: ' "$CYAN" "$TITLE" "$RESET" "$GREEN" "$DEFAULT_VALUE" "$RESET" >/dev/tty
      else
        printf '%b%s%b: ' "$CYAN" "$TITLE" "$RESET" >/dev/tty
      fi
      read -r INPUT_VALUE </dev/tty || INPUT_VALUE=""
    else
      INPUT_VALUE="$DEFAULT_VALUE"
    fi
    [ -n "$INPUT_VALUE" ] || INPUT_VALUE="$DEFAULT_VALUE"
    if ! is_valid_hostname "$INPUT_VALUE"; then
      warn "域名无效：${INPUT_VALUE:-空值}"
      continue
    fi
    printf '%s' "$INPUT_VALUE"
    return
  done
}

prompt_existing_file() {
  TITLE="$1"
  while :; do
    printf '%b%s%b: ' "$CYAN" "$TITLE" "$RESET" >/dev/tty
    read -r INPUT_FILE </dev/tty || INPUT_FILE=""
    if [ -f "$INPUT_FILE" ] && [ -r "$INPUT_FILE" ]; then
      printf '%s' "$INPUT_FILE"
      return
    fi
    warn "文件不存在或不可读：${INPUT_FILE:-空值}"
  done
}

uri_host() {
  case "$1" in
    *:*) printf '[%s]' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

choose_certificate_mode() {
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    CERT_MODE="self_signed"
    return
  fi

  headline "===== AnyTLS 证书模式 =====" >/dev/tty
  printf '%b1.%b 自动申请 ACME 证书（推荐，需要域名和 TCP 80）\n' "$GREEN" "$RESET" >/dev/tty
  printf '%b2.%b 使用已有证书\n' "$CYAN" "$RESET" >/dev/tty
  printf '%b3.%b 生成自签证书（无域名可用，客户端需开启 insecure）\n' "$YELLOW" "$RESET" >/dev/tty
  printf '请选择 [默认: 1]: ' >/dev/tty
  read -r CERT_CHOICE </dev/tty || CERT_CHOICE=""
  case "$CERT_CHOICE" in
    ""|1) CERT_MODE="acme" ;;
    2) CERT_MODE="existing" ;;
    3) CERT_MODE="self_signed" ;;
    *) error "无效选择"; exit 1 ;;
  esac
}

check_domain_resolution() {
  DOMAIN_TO_CHECK="$1"
  if ! command -v getent >/dev/null 2>&1; then
    return
  fi
  RESOLVED_IPS="$(getent ahosts "$DOMAIN_TO_CHECK" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  if [ -z "$RESOLVED_IPS" ]; then
    warn "暂时无法解析域名：$DOMAIN_TO_CHECK"
    warn "请确认域名已直接解析到当前 VPS，并且未开启普通 CDN 代理"
    return
  fi
  if ! printf '%s\n' "$RESOLVED_IPS" | grep -Fx "$PUBLIC_IP" >/dev/null 2>&1; then
    warn "域名当前解析结果中未发现本机公网 IP：$PUBLIC_IP"
    warn "解析结果：$(printf '%s' "$RESOLVED_IPS" | tr '\n' ' ')"
  fi
}

validate_certificate_pair() {
  CERTIFICATE_FILE="$1"
  PRIVATE_KEY_FILE="$2"
  CERTIFICATE_HOSTNAME="$3"
  if ! openssl x509 -in "$CERTIFICATE_FILE" -noout >/dev/null 2>&1; then
    error "证书文件格式无效"
    exit 1
  fi
  if ! openssl pkey -in "$PRIVATE_KEY_FILE" -noout >/dev/null 2>&1; then
    error "私钥文件格式无效"
    exit 1
  fi
  CERT_PUBLIC_HASH="$(openssl x509 -in "$CERTIFICATE_FILE" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  KEY_PUBLIC_HASH="$(openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  if [ -z "$CERT_PUBLIC_HASH" ] || [ "$CERT_PUBLIC_HASH" != "$KEY_PUBLIC_HASH" ]; then
    error "证书与私钥不匹配"
    exit 1
  fi
  if ! openssl x509 -in "$CERTIFICATE_FILE" -checkend 86400 -noout >/dev/null 2>&1; then
    error "证书将在 24 小时内过期或已经过期"
    exit 1
  fi
  if openssl x509 -help 2>&1 | grep -q -- '-checkhost'; then
    if ! openssl x509 -in "$CERTIFICATE_FILE" -checkhost "$CERTIFICATE_HOSTNAME" -noout >/dev/null 2>&1; then
      error "证书不包含域名：$CERTIFICATE_HOSTNAME"
      exit 1
    fi
  fi
}

backup_existing_certificate() {
  CERT_BACKUP_DIR="$TMP_DIR/cert-backup"
  mkdir -p "$CERT_BACKUP_DIR"
  if [ -f "$CERT_DIR/server.crt" ]; then
    cp "$CERT_DIR/server.crt" "$CERT_BACKUP_DIR/server.crt"
  fi
  if [ -f "$CERT_DIR/server.key" ]; then
    cp "$CERT_DIR/server.key" "$CERT_BACKUP_DIR/server.key"
  fi
}

restore_certificate_backup() {
  if [ -n "$CERT_BACKUP_DIR" ] && [ -f "$CERT_BACKUP_DIR/server.crt" ]; then
    install -m 644 "$CERT_BACKUP_DIR/server.crt" "$CERT_DIR/server.crt"
  else
    rm -f "$CERT_DIR/server.crt"
  fi
  if [ -n "$CERT_BACKUP_DIR" ] && [ -f "$CERT_BACKUP_DIR/server.key" ]; then
    install -m 600 "$CERT_BACKUP_DIR/server.key" "$CERT_DIR/server.key"
  else
    rm -f "$CERT_DIR/server.key"
  fi
  CERT_FILES_CHANGED="0"
}

prepare_certificate() {
  mkdir -p "$CONFIG_DIR" "$CERT_DIR" "$ACME_DIR"
  chmod 700 "$CONFIG_DIR" "$CERT_DIR" "$ACME_DIR"

  case "$CERT_MODE" in
    acme)
      if is_tcp_port_in_use 80; then
        error "自动 ACME 模式需要 TCP 80，但该端口已被占用"
        error "请释放 TCP 80，或改用已有证书模式"
        exit 1
      fi
      SERVER_NAME="$(prompt_hostname "AnyTLS 域名 / SNI")"
      SERVER_ADDRESS="$SERVER_NAME"
      CERT_TYPE_LABEL="ACME 自动证书"
      INSECURE="0"
      check_domain_resolution "$SERVER_NAME"
      ;;
    existing)
      if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
        error "已有证书模式需要交互输入证书路径"
        exit 1
      fi
      SERVER_NAME="$(prompt_hostname "证书对应的域名 / SNI")"
      SOURCE_CERT="$(prompt_existing_file "证书完整链路径")"
      SOURCE_KEY="$(prompt_existing_file "证书私钥路径")"
      validate_certificate_pair "$SOURCE_CERT" "$SOURCE_KEY" "$SERVER_NAME"
      CERT_FILES_CHANGED="1"
      install -m 644 "$SOURCE_CERT" "$CERT_DIR/server.crt"
      install -m 600 "$SOURCE_KEY" "$CERT_DIR/server.key"
      SERVER_ADDRESS="$SERVER_NAME"
      CERT_TYPE_LABEL="已有可信证书"
      INSECURE="0"
      ;;
    self_signed)
      SERVER_NAME="$(prompt_hostname "自签证书 SNI" "$DEFAULT_SNI")"
      CERT_FILES_CHANGED="1"
      openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -days 3650 \
        -subj "/CN=${SERVER_NAME}" \
        -addext "subjectAltName=DNS:${SERVER_NAME}" >/dev/null 2>&1
      chmod 600 "$CERT_DIR/server.key"
      chmod 644 "$CERT_DIR/server.crt"
      SERVER_ADDRESS="$PUBLIC_IP"
      CERT_TYPE_LABEL="自签证书（客户端需开启 insecure）"
      INSECURE="1"
      ;;
    *)
      error "未知证书模式：$CERT_MODE"
      exit 1
      ;;
  esac
}

write_config() {
  NEW_CONFIG="$CONFIG_FILE.new"
  case "$PUBLIC_IP" in
    *:*) LISTEN_ADDRESS="::" ;;
    *) LISTEN_ADDRESS="0.0.0.0" ;;
  esac
  cat >"$NEW_CONFIG" <<CONFIG
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "${LISTEN_ADDRESS}",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "default",
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "min_version": "1.3",
CONFIG

  if [ "$CERT_MODE" = "acme" ]; then
    cat >>"$NEW_CONFIG" <<CONFIG
        "certificate_provider": {
          "type": "acme",
          "domain": ["${SERVER_NAME}"],
          "default_server_name": "${SERVER_NAME}",
          "key_type": "p256",
          "data_directory": "${ACME_DIR}"
        }
CONFIG
  else
    cat >>"$NEW_CONFIG" <<CONFIG
        "certificate_path": "${CERT_DIR}/server.crt",
        "key_path": "${CERT_DIR}/server.key"
CONFIG
  fi

  cat >>"$NEW_CONFIG" <<CONFIG
      }
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

  chmod 600 "$NEW_CONFIG"
  jq empty "$NEW_CONFIG"
  "$BINARY_FILE" check -c "$NEW_CONFIG"
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
Description=sing-box AnyTLS Service
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
description="sing-box AnyTLS Service"
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
  WAIT_COUNT=0
  while [ "$WAIT_COUNT" -lt 15 ]; do
    if service_is_running; then
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
  ss -tnlp | grep ":${PORT} " || netstat -tnlp | grep ":${PORT} " || true
}

build_share_link() {
  URI_SERVER="$(uri_host "$SERVER_ADDRESS")"
  if [ "$INSECURE" = "1" ]; then
    printf '%s' "anytls://${PASSWORD}@${URI_SERVER}:${PORT}/?sni=${SERVER_NAME}&insecure=1#AnyTLS-${PORT}"
  else
    printf '%s' "anytls://${PASSWORD}@${URI_SERVER}:${PORT}/?sni=${SERVER_NAME}#AnyTLS-${PORT}"
  fi
}

write_node_info() {
  SHARE_LINK="$(build_share_link)"
  cat >"$NODE_INFO_FILE" <<INFO
===== AnyTLS 节点信息 =====

服务器地址：$SERVER_ADDRESS

公网 IP：$PUBLIC_IP

端口：$PORT

密码：$PASSWORD

SNI：$SERVER_NAME

证书：$CERT_TYPE_LABEL

sing-box 版本：$SING_BOX_VERSION

服务名：$SERVICE_NAME

链接：$SHARE_LINK

===== 常用命令 =====
查看节点信息：/root/install-anytls.sh info

查看服务状态：
systemctl status $SERVICE_NAME --no-pager -l

查看监听端口：ss -tnlp | grep :${PORT}

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
      /^(服务器地址|公网 IP|端口|密码|SNI|证书|sing-box 版本|服务名|配置文件|节点信息文件|查看节点信息|查看服务状态|查看监听端口|检查配置)：/ { print cyan $0 reset; next }
      /^链接：anytls:\/\// { print yellow $0 reset; next }
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
  warn "未找到已保存的 AnyTLS 节点信息"
  exit 1
}

choose_action_if_installed() {
  if [ ! -f "$NODE_INFO_FILE" ] && [ ! -f "$NODE_INFO_COPY" ]; then
    return
  fi
  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    return
  fi
  info "检测到已保存的 AnyTLS 节点信息"
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
  headline "===== 最终节点信息 ====="
  echo
  printf '%b服务器地址：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$SERVER_ADDRESS" "$RESET"
  printf '%b公网 IP：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PUBLIC_IP" "$RESET"
  printf '%b端口：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PORT" "$RESET"
  printf '%b密码：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$PASSWORD" "$RESET"
  printf '%bSNI：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$SERVER_NAME" "$RESET"
  printf '%b证书：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$CERT_TYPE_LABEL" "$RESET"
  printf '%b服务名：%b\n%b%s%b\n' "$CYAN" "$RESET" "$GREEN" "$SERVICE_NAME" "$RESET"
  echo
  printf '%bAnyTLS 链接%b\n' "$BOLD$BLUE" "$RESET"
  printf '%b%s%b\n' "$YELLOW" "$SHARE_LINK" "$RESET"
  echo
  printf '%b节点信息文件：%b\n' "$CYAN" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
  printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
  if [ "$INSECURE" = "1" ]; then
    echo
    warn "当前使用自签证书，客户端必须开启 insecure / 跳过证书验证。"
  fi
}

case "${1:-}" in
  info|show|view|--info|--show|--view) show_node_info; exit 0 ;;
  install|--install|"") ;;
  *)
    headline "用法："
    printf '%s\n' "  $0              安装或在已安装时显示菜单"
    printf '%s\n' "  $0 install      直接安装 / 重装"
    printf '%s\n' "  $0 info         查看已保存的 AnyTLS 节点信息"
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
PASSWORD="$(prompt_password)"
choose_certificate_mode
install_sing_box
backup_existing_certificate
prepare_certificate
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
  error "AnyTLS 服务启动失败"
  show_status
  if [ -n "$ROLLBACK_CONFIG" ] && [ -f "$ROLLBACK_CONFIG" ]; then
    warn "正在恢复旧配置并尝试重新启动原服务"
    mv -f "$ROLLBACK_CONFIG" "$CONFIG_FILE"
    restore_certificate_backup
    start_service >/dev/null 2>&1 || true
  fi
  exit 1
fi

rm -f "$ROLLBACK_CONFIG"
CERT_FILES_CHANGED="0"
write_node_info

echo
headline "===== 服务状态 ====="
show_status
echo
success "AnyTLS 节点信息已保存到："
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_FILE" "$RESET"
printf '%b%s%b\n' "$GREEN" "$NODE_INFO_COPY" "$RESET"
echo
show_final_summary
