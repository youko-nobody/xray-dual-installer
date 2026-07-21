#!/usr/bin/env bash
set -euo pipefail

stop_systemd_service() {
  local service_name="$1"
  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    systemctl disable --now "$service_name" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload
  fi
}

stop_openrc_service() {
  local service_name="$1"
  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$service_name" stop >/dev/null 2>&1 || true
    rc-update del "$service_name" default >/dev/null 2>&1 || true
    rm -f "/etc/init.d/${service_name}"
  fi
}

pkill -f "/usr/local/bin/xray run -config /usr/local/etc/xray/config.json" 2>/dev/null || true

stop_systemd_service "xray"
stop_openrc_service "xray"

rm -f /root/start-xray.sh
rm -f /root/xray-node-info.txt
rm -f /usr/local/bin/xray
rm -rf /usr/local/etc/xray
rm -f /var/log/xray.log
rm -f /var/log/xray-access.log
rm -f /var/log/xray-error.log

echo "Xray 双节点已卸载。"
echo "已删除以下文件："
echo "- /usr/local/bin/xray"
echo "- /usr/local/etc/xray"
echo "- /root/start-xray.sh"
echo "- /root/xray-node-info.txt"
echo "- /var/log/xray.log"
echo "- /var/log/xray-access.log"
echo "- /var/log/xray-error.log"
