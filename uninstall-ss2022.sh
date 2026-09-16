#!/bin/sh
set -e

SERVICE_NAME="sing-box-ss2022"
BINARY_FILE="/usr/local/bin/sing-box-ss2022"
CONFIG_DIR="/etc/sing-box-ss2022"
CONFIG_FILE="$CONFIG_DIR/config.json"

stop_systemd_service() {
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
  fi
}

stop_openrc_service() {
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
    rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
    rm -f "/etc/init.d/${SERVICE_NAME}"
  fi
}

pkill -f "$BINARY_FILE run -c $CONFIG_FILE" 2>/dev/null || true
stop_systemd_service
stop_openrc_service

rm -f "$BINARY_FILE"
rm -f /root/ss2022-node-info.txt
rm -f /root/start-sing-box-ss2022.sh
rm -f /var/log/sing-box-ss2022.log
rm -rf "$CONFIG_DIR"

echo "SS2022 节点已卸载。"
echo "已删除以下文件："
echo "- $BINARY_FILE"
echo "- $CONFIG_DIR"
echo "- /root/ss2022-node-info.txt"
echo "- /root/start-sing-box-ss2022.sh"
echo "- /var/log/sing-box-ss2022.log"
