#!/bin/sh
set -e

SERVICE_NAME="xray-socks5"
CONFIG_FILE="/usr/local/etc/xray/socks5-config.json"

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

pkill -f "run -config $CONFIG_FILE" 2>/dev/null || true
stop_systemd_service "$SERVICE_NAME"
stop_openrc_service "$SERVICE_NAME"

rm -f "$CONFIG_FILE"
rm -f /usr/local/etc/xray/socks5-node-info.txt
rm -f /root/socks5-node-info.txt
rm -f /root/start-xray-socks5.sh
rm -f /var/log/xray-socks5-access.log
rm -f /var/log/xray-socks5-error.log
rm -f /var/log/xray-socks5.log

echo "SOCKS5 节点已卸载。"
echo "已删除以下文件："
echo "- $CONFIG_FILE"
echo "- /usr/local/etc/xray/socks5-node-info.txt"
echo "- /root/socks5-node-info.txt"
echo "- /root/start-xray-socks5.sh"
echo "- /var/log/xray-socks5-access.log"
echo "- /var/log/xray-socks5-error.log"
echo "- /var/log/xray-socks5.log"
