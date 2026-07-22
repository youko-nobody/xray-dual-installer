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
  printf '%b4.%b 查看已保存的节点信息\n' "$CYAN" "$RESET"
  printf '%b5.%b 卸载节点\n' "$YELLOW" "$RESET"
  printf '%b0.%b 退出\n' "$RED" "$RESET"
  echo
  warn "提示：选 1 或 2 会覆盖当前 Xray 配置；HY2 可以和 Xray 共存。"
  echo
}

show_info_menu() {
  headline "===== 查看节点信息 ====="
  echo
  printf '%b1.%b 查看单 Reality 节点\n' "$GREEN" "$RESET"
  printf '%b2.%b 查看 Xray 双节点\n' "$GREEN" "$RESET"
  printf '%b3.%b 查看 HY2 节点\n' "$GREEN" "$RESET"
  printf '%b0.%b 返回\n' "$YELLOW" "$RESET"
  echo
  printf '请选择 [默认: 0]: '
  read -r INFO_CHOICE || INFO_CHOICE=""

  case "$INFO_CHOICE" in
    1)
      ensure_script "install-reality.sh" "/root/install-reality.sh"
      /root/install-reality.sh info
      ;;
    2)
      ensure_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh"
      /root/install-xray-dual-auto.sh info
      ;;
    3)
      ensure_script "install-hy2.sh" "/root/install-hy2.sh"
      /root/install-hy2.sh info
      ;;
    ""|0)
      return
      ;;
    *)
      error "无效选择"
      ;;
  esac
}

show_uninstall_menu() {
  headline "===== 卸载节点 ====="
  echo
  printf '%b1.%b 卸载单 Reality 节点\n' "$YELLOW" "$RESET"
  printf '%b2.%b 卸载 Xray 双节点\n' "$YELLOW" "$RESET"
  printf '%b3.%b 卸载 HY2 节点\n' "$YELLOW" "$RESET"
  printf '%b4.%b 卸载 Xray + HY2 全部节点\n' "$RED" "$RESET"
  printf '%b0.%b 返回\n' "$CYAN" "$RESET"
  echo
  printf '请选择 [默认: 0]: '
  read -r UNINSTALL_CHOICE || UNINSTALL_CHOICE=""

  case "$UNINSTALL_CHOICE" in
    1)
      run_remote_script "uninstall-reality.sh" "/root/uninstall-reality.sh"
      ;;
    2)
      run_remote_script "uninstall-xray-dual.sh" "/root/uninstall-xray-dual.sh"
      ;;
    3)
      run_remote_script "uninstall-hy2.sh" "/root/uninstall-hy2.sh"
      ;;
    4)
      warn "即将卸载 Xray 和 HY2 相关节点。"
      printf '确认卸载全部？输入 yes 继续: '
      read -r CONFIRM || CONFIRM=""
      if [ "$CONFIRM" = "yes" ]; then
        run_remote_script "uninstall-xray-dual.sh" "/root/uninstall-xray-dual.sh"
        run_remote_script "uninstall-hy2.sh" "/root/uninstall-hy2.sh"
      else
        warn "已取消卸载。"
      fi
      ;;
    ""|0)
      return
      ;;
    *)
      error "无效选择"
      ;;
  esac
}

main() {
  require_root

  case "${1:-}" in
    reality)
      run_remote_script "install-reality.sh" "/root/install-reality.sh" install
      exit 0
      ;;
    dual)
      run_remote_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh" install
      exit 0
      ;;
    hy2)
      run_remote_script "install-hy2.sh" "/root/install-hy2.sh" install
      exit 0
      ;;
    info)
      show_info_menu
      exit 0
      ;;
    uninstall)
      show_uninstall_menu
      exit 0
      ;;
    ""|menu)
      ;;
    *)
      headline "用法："
      printf '%s\n' "  $0             打开综合菜单"
      printf '%s\n' "  $0 reality     直接部署单 Reality"
      printf '%s\n' "  $0 dual        直接部署 Xray 双节点"
      printf '%s\n' "  $0 hy2         直接部署 HY2"
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
      ""|1)
        run_remote_script "install-reality.sh" "/root/install-reality.sh" install
        pause_hint
        exit 0
        ;;
      2)
        run_remote_script "install-xray-dual-auto.sh" "/root/install-xray-dual-auto.sh" install
        pause_hint
        exit 0
        ;;
      3)
        run_remote_script "install-hy2.sh" "/root/install-hy2.sh" install
        pause_hint
        exit 0
        ;;
      4)
        show_info_menu
        ;;
      5)
        show_uninstall_menu
        ;;
      0)
        success "已退出。"
        exit 0
        ;;
      *)
        error "无效选择，请重新输入。"
        ;;
    esac
  done
}

main "$@"
