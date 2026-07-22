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

pkill -f "/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml" 2>/dev/null || true

stop_systemd_service "hysteria-server"
stop_openrc_service "hysteria"

rm -f /usr/local/bin/hysteria
rm -rf /etc/hysteria
rm -f /root/start-hy2.sh
rm -f /root/hy2-node-info.txt
rm -f /var/log/hysteria.log

echo "HY2 节点已卸载。"
echo "已删除以下文件："
echo "- /usr/local/bin/hysteria"
echo "- /etc/hysteria"
echo "- /root/start-hy2.sh"
echo "- /root/hy2-node-info.txt"
echo "- /var/log/hysteria.log"
