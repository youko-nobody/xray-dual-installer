#!/bin/sh
set -e

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"

stop_systemd_service() {
  service_name="$1"
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl disable --now "$service_name" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload
  fi
}

stop_openrc_service() {
  service_name="$1"
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$service_name" stop >/dev/null 2>&1 || true
    rc-update del "$service_name" default >/dev/null 2>&1 || true
    rm -f "/etc/init.d/${service_name}"
  fi
}

cleanup_shared_xray() {
  if [ ! -f "$CONFIG_DIR/config.json" ] &&
     [ ! -f "$CONFIG_DIR/reality-config.json" ] &&
     [ ! -f "$CONFIG_DIR/socks5-config.json" ]; then
    rm -f /usr/local/bin/xray
  fi
  rmdir "$CONFIG_DIR" 2>/dev/null || true
}

pkill -f "/usr/local/bin/xray run -config $CONFIG_FILE" 2>/dev/null || true

stop_systemd_service "xray"
stop_openrc_service "xray"

rm -f /root/start-xray.sh
rm -f /root/xray-node-info.txt
rm -f "$CONFIG_FILE"
rm -f "$CONFIG_DIR/node-info.txt"
rm -f /var/log/xray.log
rm -f /var/log/xray-access.log
rm -f /var/log/xray-error.log
cleanup_shared_xray

echo "Xray 双节点已卸载。"
echo "已删除以下文件："
echo "- $CONFIG_FILE"
echo "- $CONFIG_DIR/node-info.txt"
echo "- /root/start-xray.sh"
echo "- /root/xray-node-info.txt"
echo "- /var/log/xray.log"
echo "- /var/log/xray-access.log"
echo "- /var/log/xray-error.log"
