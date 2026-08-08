#!/bin/sh
set -e

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

pkill -f "/usr/local/bin/snell-server -c /etc/snell/snell-server.conf" 2>/dev/null || true

stop_systemd_service "snell"
stop_openrc_service "snell"

rm -f /usr/local/bin/snell-server
rm -rf /etc/snell
rm -f /root/start-snell.sh
rm -f /root/snell-node-info.txt
rm -f /var/log/snell.log

echo "Snell 节点已卸载。"
echo "已删除以下文件："
echo "- /usr/local/bin/snell-server"
echo "- /etc/snell"
echo "- /root/start-snell.sh"
echo "- /root/snell-node-info.txt"
echo "- /var/log/snell.log"
