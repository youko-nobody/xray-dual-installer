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

pkill -f "/usr/local/bin/mtproto-proxy" 2>/dev/null || true

stop_systemd_service "mtproxy"
stop_openrc_service "mtproxy"

rm -f /usr/local/bin/mtproto-proxy
rm -rf /etc/mtproto-proxy
rm -rf /usr/local/src/MTProxy
rm -f /root/start-mtproto.sh
rm -f /root/mtproto-node-info.txt
rm -f /var/log/mtproto.log

echo "MTProto 节点已卸载。"
echo "已删除以下文件："
echo "- /usr/local/bin/mtproto-proxy"
echo "- /etc/mtproto-proxy"
echo "- /usr/local/src/MTProxy"
echo "- /root/start-mtproto.sh"
echo "- /root/mtproto-node-info.txt"
echo "- /var/log/mtproto.log"
