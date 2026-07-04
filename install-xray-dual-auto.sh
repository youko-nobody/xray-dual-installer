#!/bin/sh
set -e

SNI="www.sony.com"
WS_PATH="/ws"

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip openssl ca-certificates net-tools procps
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget unzip openssl ca-certificates net-tools procps
  else
    echo "Unsupported system: no apt-get or apk found"
    exit 1
  fi
}

detect_ip() {
  IP="$(wget -qO- https://api.ipify.org || true)"
  [ -n "$IP" ] || IP="$(wget -qO- https://ifconfig.me || true)"
  [ -n "$IP" ] || IP="$(wget -qO- https://ip.sb || true)"
  [ -n "$IP" ] || IP="$(wget -qO- https://icanhazip.com || true)"
  [ -n "$IP" ] || {
    echo "Failed to detect public IP"
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
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
}

random_port() {
  while :; do
    CANDIDATE="$(awk 'BEGIN{srand(); print int(20000 + rand() * 30000)}')"
    if ! ss -lnt "( sport = :$CANDIDATE )" 2>/dev/null | grep -q ":$CANDIDATE"; then
      printf '%s' "$CANDIDATE"
      return
    fi
    sleep 1
  done
}

prompt_port() {
  LABEL="$1"
  DEFAULT_VALUE="$2"
  printf '%s [default: %s]: ' "$LABEL" "$DEFAULT_VALUE"
  read -r INPUT_VALUE
  if [ -n "$INPUT_VALUE" ]; then
    printf '%s' "$INPUT_VALUE"
  else
    printf '%s' "$DEFAULT_VALUE"
  fi
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

install_deps

PUBLIC_IP="$(detect_ip)"
XRAY_ZIP="$(detect_xray_zip)"
DEFAULT_REALITY_PORT="$(random_port)"
DEFAULT_WS_PORT="$(random_port)"

while [ "$DEFAULT_WS_PORT" = "$DEFAULT_REALITY_PORT" ]; do
  DEFAULT_WS_PORT="$(random_port)"
done

echo "Detected public IP: $PUBLIC_IP"
REALITY_PORT="$(prompt_port "Reality port" "$DEFAULT_REALITY_PORT")"
WS_PORT="$(prompt_port "WS port" "$DEFAULT_WS_PORT")"

if [ "$REALITY_PORT" = "$WS_PORT" ]; then
  echo "Reality port and WS port cannot be the same"
  exit 1
fi

cd /root
rm -f xray.zip xray
wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/${XRAY_ZIP}"
unzip -o xray.zip
install -m 755 xray /usr/local/bin/xray
mkdir -p /usr/local/etc/xray

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

echo
echo "===== Public IP ====="
echo "$PUBLIC_IP"
echo
echo "===== Reality ====="
echo "Port: $REALITY_PORT"
echo "vless://${REALITY_UUID}@${PUBLIC_IP}:${REALITY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Reality-${PUBLIC_IP}-${REALITY_PORT}"
echo
echo "===== WS ====="
echo "Port: $WS_PORT"
echo "vless://${WS_UUID}@${PUBLIC_IP}:${WS_PORT}?type=ws&security=none&path=%2Fws#WS-${PUBLIC_IP}-${WS_PORT}"
echo
echo "===== Status ====="
show_status
