#!/bin/sh
set -e

BASE_URL="https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main"

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

require_root() {
  if [ "$(id -u)" != "0" ]; then
    error "请使用 root 用户运行此脚本"
    exit 1
  fi
}

fetch_file() {
  REMOTE_NAME="$1"
  LOCAL_PATH="$2"
  info "正在获取脚本：$REMOTE_NAME"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$LOCAL_PATH" "$BASE_URL/$REMOTE_NAME"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$LOCAL_PATH" "$BASE_URL/$REMOTE_NAME"
  else
    error "未找到 curl 或 wget，无法下载脚本"
    exit 1
  fi
  chmod +x "$LOCAL_PATH"
}

ensure_script() {
  REMOTE_NAME="$1"
  LOCAL_PATH="$2"
  if [ ! -f "$LOCAL_PATH" ]; then
    fetch_file "$REMOTE_NAME" "$LOCAL_PATH"
  else
    chmod +x "$LOCAL_PATH"
  fi
}

node_is_saved() {
  [ -s "$1" ]
}

print_overview_row() {
  LABEL="$1"
  PADDING="$2"
  NODE_FILE="$3"
  if node_is_saved "$NODE_FILE"; then
    LABEL_COLOR="$BOLD$GREEN"
    STATUS_COLOR="$BOLD$GREEN"
    STATUS_TEXT="已保存"
  else
    LABEL_COLOR="$CYAN"
    STATUS_COLOR="$YELLOW"
    STATUS_TEXT="未保存"
  fi
  printf '%b%s%*s%b：%b%s%b\n' \
    "$LABEL_COLOR" "$LABEL" "$PADDING" "" "$RESET" \
    "$STATUS_COLOR" "$STATUS_TEXT" "$RESET"
}

print_info_menu_item() {
  ITEM_NUMBER="$1"
  ITEM_LABEL="$2"
  NODE_FILE="$3"
  if node_is_saved "$NODE_FILE"; then
    printf '%b%s. %s（已保存）%b\n' "$BOLD$GREEN" "$ITEM_NUMBER" "$ITEM_LABEL" "$RESET"
  else
    printf '%b%s.%b %s\n' "$GREEN" "$ITEM_NUMBER" "$RESET" "$ITEM_LABEL"
  fi
}

show_saved_overview() {
  headline "===== 已保存节点总览 ====="
  echo
  print_overview_row "Reality" 2 "/usr/local/etc/xray/reality-node-info.txt"
  print_overview_row "双节点" 3 "/usr/local/etc/xray/node-info.txt"
  print_overview_row "HY2" 6 "/etc/hysteria/node-info.txt"
  print_overview_row "Snell v6" 1 "/etc/snell/node-info.txt"
  print_overview_row "SOCKS5" 3 "/usr/local/etc/xray/socks5-node-info.txt"
  print_overview_row "MTProto" 2 "/etc/mtproto-proxy/node-info.txt"
  print_overview_row "AnyTLS" 3 "/etc/sing-box-anytls/node-info.txt"
  print_overview_row "SS2022" 3 "/etc/sing-box-ss2022/node-info.txt"
  echo
}

run_remote_script() {
  REMOTE_NAME="$1"
  LOCAL_PATH="$2"
  ACTION="${3:-install}"
  fetch_file "$REMOTE_NAME" "$LOCAL_PATH"
  "$LOCAL_PATH" "$ACTION"
}

pause_hint() {
  echo
  info "操作完成。"
}

show_menu() {
  headline "===== 综合节点一键脚本 ====="
  echo
  printf '%b1.%b VLESS + Reality 单节点\n' "$GREEN" "$RESET"
  printf '%b2.%b VLESS + Reality + VLESS + WS 双节点\n' "$GREEN" "$RESET"
  printf '%b3.%b Hysteria2 / HY2 节点\n' "$GREEN" "$RESET"
  printf '%b4.%b Snell v6 节点\n' "$GREEN" "$RESET"
  printf '%b5.%b SOCKS5 节点\n' "$GREEN" "$RESET"
  printf '%b6.%b MTProto 节点\n' "$GREEN" "$RESET"
  printf '%b7.%b AnyTLS 节点\n' "$GREEN" "$RESET"
  printf '%b8.%b Shadowsocks 2022 节点\n' "$GREEN" "$RESET"
  printf '%b9.%b 查看已保存的节点信息\n' "$CYAN" "$RESET"
  printf '%b10.%b 卸载节点\n' "$YELLOW" "$RESET"
  printf '%b0.%b 退出\n' "$RED" "$RESET"
  echo
  warn "提示：Reality、SOCKS5、AnyTLS 与 SS2022 可独立共存；双节点仍会占用自己的 Xray 配置。"
}

show_info_menu() {
  headline "===== 查看节点信息 ====="
  show_saved_overview
  echo
  print_info_menu_item 1 "查看单 Reality 节点" "/usr/local/etc/xray/reality-node-info.txt"
  print_info_menu_item 2 "查看 Xray 双节点" "/usr/local/etc/xray/node-info.txt"
  print_info_menu_item 3 "查看 HY2 节点" "/etc/hysteria/node-info.txt"
  print_info_menu_item 4 "查看 Snell v6 节点" "/etc/snell/node-info.txt"
  print_info_menu_item 5 "查看 SOCKS5 节点" "/usr/local/etc/xray/socks5-node-info.txt"
  print_info_menu_item 6 "查看 MTProto 节点" "/etc/mtproto-proxy/node-info.txt"
  print_info_menu_item 7 "查看 AnyTLS 节点" "/etc/sing-box-anytls/node-info.txt"
  print_info_menu_item 8 "查看 SS2022 节点" "/etc/sing-box-ss2022/node-info.txt"
  printf '%b9.%b 查看全部已保存节点内容\n' "$CYAN" "$RESET"
  printf '%b0.%b 返回\n' "$YELLOW" "$RESET"
  echo
  printf '请选择 [默认: 0]: '
  read -r INFO_CHOICE || INFO_CHOICE=""
  case "$INFO_CHOICE" in
    1) ensure_script "install-reality.sh" "/root/install-reality.sh"; /root/install-reality.sh info ;;
    2) ensure_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh"; /root/install-xray-dual-auto.sh info ;;
    3) ensure_script "install-hy2.sh" "/root/install-hy2.sh"; /root/install-hy2.sh info ;;
    4) ensure_script "install-snell.sh" "/root/install-snell.sh"; /root/install-snell.sh info ;;
    5) ensure_script "install-socks5.sh" "/root/install-socks5.sh"; /root/install-socks5.sh info ;;
    6) ensure_script "install-mtproto.sh" "/root/install-mtproto.sh"; /root/install-mtproto.sh info ;;
    7) ensure_script "install-anytls.sh" "/root/install-anytls.sh"; /root/install-anytls.sh info ;;
    8) ensure_script "install-ss2022.sh" "/root/install-ss2022.sh"; /root/install-ss2022.sh info ;;
    9)
      show_saved_overview
      echo
      for file in \
        "/usr/local/etc/xray/reality-node-info.txt" \
        "/usr/local/etc/xray/node-info.txt" \
        "/etc/hysteria/node-info.txt" \
        "/etc/snell/node-info.txt" \
        "/usr/local/etc/xray/socks5-node-info.txt" \
        "/etc/mtproto-proxy/node-info.txt" \
        "/etc/sing-box-anytls/node-info.txt" \
        "/etc/sing-box-ss2022/node-info.txt"
      do
        [ -s "$file" ] && cat "$file" && echo
      done
      ;;
    ""|0) return ;;
    *) error "无效选择" ;;
  esac
}

show_uninstall_menu() {
  headline "===== 卸载节点 ====="
  echo
  printf '%b1.%b 卸载单 Reality 节点\n' "$YELLOW" "$RESET"
  printf '%b2.%b 卸载 Xray 双节点\n' "$YELLOW" "$RESET"
  printf '%b3.%b 卸载 HY2 节点\n' "$YELLOW" "$RESET"
  printf '%b4.%b 卸载 Snell v6 节点\n' "$YELLOW" "$RESET"
  printf '%b5.%b 卸载 SOCKS5 节点\n' "$YELLOW" "$RESET"
  printf '%b6.%b 卸载 MTProto 节点\n' "$YELLOW" "$RESET"
  printf '%b7.%b 卸载 AnyTLS 节点\n' "$YELLOW" "$RESET"
  printf '%b8.%b 卸载 SS2022 节点\n' "$YELLOW" "$RESET"
  printf '%b9.%b 卸载 Xray + HY2 + Snell + SOCKS5 + MTProto + AnyTLS + SS2022 全部节点\n' "$RED" "$RESET"
  printf '%b0.%b 返回\n' "$CYAN" "$RESET"
  echo
  printf '请选择 [默认: 0]: '
  read -r UNINSTALL_CHOICE || UNINSTALL_CHOICE=""
  case "$UNINSTALL_CHOICE" in
    1) run_remote_script "uninstall-reality.sh" "/root/uninstall-reality.sh" ;;
    2) run_remote_script "uninstall-xray-dual.sh" "/root/uninstall-xray-dual.sh" ;;
    3) run_remote_script "uninstall-hy2.sh" "/root/uninstall-hy2.sh" ;;
    4) run_remote_script "uninstall-snell.sh" "/root/uninstall-snell.sh" ;;
    5) run_remote_script "uninstall-socks5.sh" "/root/uninstall-socks5.sh" ;;
    6) run_remote_script "uninstall-mtproto.sh" "/root/uninstall-mtproto.sh" ;;
    7) run_remote_script "uninstall-anytls.sh" "/root/uninstall-anytls.sh" ;;
    8) run_remote_script "uninstall-ss2022.sh" "/root/uninstall-ss2022.sh" ;;
    9)
      warn "即将卸载 Xray、HY2、Snell、SOCKS5、MTProto、AnyTLS、SS2022 相关节点。"
      printf '确认卸载全部？输入 yes 继续: '
      read -r CONFIRM || CONFIRM=""
      if [ "$CONFIRM" = "yes" ]; then
        run_remote_script "uninstall-xray-dual.sh" "/root/uninstall-xray-dual.sh"
        run_remote_script "uninstall-hy2.sh" "/root/uninstall-hy2.sh"
        run_remote_script "uninstall-snell.sh" "/root/uninstall-snell.sh"
        run_remote_script "uninstall-socks5.sh" "/root/uninstall-socks5.sh"
        run_remote_script "uninstall-mtproto.sh" "/root/uninstall-mtproto.sh"
        run_remote_script "uninstall-anytls.sh" "/root/uninstall-anytls.sh"
        run_remote_script "uninstall-ss2022.sh" "/root/uninstall-ss2022.sh"
      else
        warn "已取消卸载。"
      fi
      ;;
    ""|0) return ;;
    *) error "无效选择" ;;
  esac
}

main() {
  require_root
  case "${1:-}" in
    reality) run_remote_script "install-reality.sh" "/root/install-reality.sh" install; exit 0 ;;
    dual) run_remote_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh" install; exit 0 ;;
    hy2) run_remote_script "install-hy2.sh" "/root/install-hy2.sh" install; exit 0 ;;
    snell) run_remote_script "install-snell.sh" "/root/install-snell.sh" install; exit 0 ;;
    socks5) run_remote_script "install-socks5.sh" "/root/install-socks5.sh" install; exit 0 ;;
    mtproto) run_remote_script "install-mtproto.sh" "/root/install-mtproto.sh" install; exit 0 ;;
    anytls) run_remote_script "install-anytls.sh" "/root/install-anytls.sh" install; exit 0 ;;
    ss2022) run_remote_script "install-ss2022.sh" "/root/install-ss2022.sh" install; exit 0 ;;
    info) show_info_menu; exit 0 ;;
    uninstall) show_uninstall_menu; exit 0 ;;
    ""|menu) ;;
    *)
      headline "用法："
      printf '%s\n' "  $0             打开综合菜单"
      printf '%s\n' "  $0 reality     直接部署单 Reality"
      printf '%s\n' "  $0 dual        直接部署 Xray 双节点"
      printf '%s\n' "  $0 hy2         直接部署 HY2"
      printf '%s\n' "  $0 snell       直接部署 Snell v6"
      printf '%s\n' "  $0 socks5      直接部署 SOCKS5"
      printf '%s\n' "  $0 mtproto     直接部署 MTProto"
      printf '%s\n' "  $0 anytls      直接部署 AnyTLS"
      printf '%s\n' "  $0 ss2022      直接部署 Shadowsocks 2022"
      printf '%s\n' "  $0 info        查看节点信息菜单"
      printf '%s\n' "  $0 uninstall   卸载菜单"
      exit 1
      ;;
  esac

  while :; do
    show_menu
    printf '请选择 [默认: 1]: '
    read -r CHOICE || CHOICE=""
    case "$CHOICE" in
      ""|1) run_remote_script "install-reality.sh" "/root/install-reality.sh" install; pause_hint; exit 0 ;;
      2) run_remote_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh" install; pause_hint; exit 0 ;;
      3) run_remote_script "install-hy2.sh" "/root/install-hy2.sh" install; pause_hint; exit 0 ;;
      4) run_remote_script "install-snell.sh" "/root/install-snell.sh" install; pause_hint; exit 0 ;;
      5) run_remote_script "install-socks5.sh" "/root/install-socks5.sh" install; pause_hint; exit 0 ;;
      6) run_remote_script "install-mtproto.sh" "/root/install-mtproto.sh" install; pause_hint; exit 0 ;;
      7) run_remote_script "install-anytls.sh" "/root/install-anytls.sh" install; pause_hint; exit 0 ;;
      8) run_remote_script "install-ss2022.sh" "/root/install-ss2022.sh" install; pause_hint; exit 0 ;;
      9) show_info_menu ;;
      10) show_uninstall_menu ;;
      0) success "已退出。"; exit 0 ;;
      *) error "无效选择，请重新输入。" ;;
    esac
  done
}

main "$@"
