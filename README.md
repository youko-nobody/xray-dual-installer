# Xray & HY2 Installer

![Shell](https://img.shields.io/badge/Shell-sh-4EAA25?style=for-the-badge)
![System](https://img.shields.io/badge/System-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=for-the-badge)
![Service](https://img.shields.io/badge/Service-systemd%20%7C%20OpenRC-f97316?style=for-the-badge)
![HY2](https://img.shields.io/badge/HY2-Hysteria2-9333ea?style=for-the-badge)
![Language](https://img.shields.io/badge/Prompt-%E4%B8%AD%E6%96%87-e11d48?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-16a34a?style=for-the-badge)

一个中文化的一键安装脚本仓库，用来快速部署：

- `VLESS + Reality`
- `VLESS + WS`
- `Hysteria2 / HY2`

脚本会自动安装依赖、获取公网 IP、生成节点参数、配置开机自启，并且把节点链接保存到本机，后续可以随时查看。

> [!TIP]
> 适合想快速部署双节点、并且希望后续能一条命令找回节点信息的自用场景。

## Xray 双节点快速安装

直接复制执行：

```sh
wget -O /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

如果系统里没有 `wget`，可以用 `curl`：

```sh
curl -L -o /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

> [!IMPORTANT]
> 请使用 `root` 用户执行脚本。安装完成后，请放行你选择的 Reality 和 WS 两个 TCP 端口。

## HY2 快速安装

直接复制执行：

```sh
wget -O /root/install-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-hy2.sh && chmod +x /root/install-hy2.sh && /root/install-hy2.sh
```

如果系统里没有 `wget`，可以用 `curl`：

```sh
curl -L -o /root/install-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-hy2.sh && chmod +x /root/install-hy2.sh && /root/install-hy2.sh
```

> [!IMPORTANT]
> HY2 使用 `UDP`，安装完成后请放行你选择的 `UDP` 端口。默认端口是 `8443/UDP`。

## 查看节点信息

### 查看 Xray 节点

安装完成后，如果第一次没有保存输出内容，后续直接执行：

```sh
/root/install-xray-dual-auto.sh info
```

节点信息会同时保存到：

```sh
/usr/local/etc/xray/node-info.txt
/root/xray-node-info.txt
```

再次运行安装脚本时，如果检测到已经保存过节点信息，会显示中文菜单：

```text
1. 查看节点信息
2. 重新安装 / 覆盖节点
```

> [!NOTE]
> 节点信息只保存在 VPS 本机，不会上传到 GitHub。

### 查看 HY2 节点

```sh
/root/install-hy2.sh info
```

HY2 节点信息会保存到：

```sh
/etc/hysteria/node-info.txt
/root/hy2-node-info.txt
```

## 一键卸载

### 卸载 Xray 双节点

直接复制执行：

```sh
wget -O /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
```

如果系统里没有 `wget`，可以用 `curl`：

```sh
curl -L -o /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
```

### 卸载 HY2

```sh
wget -O /root/uninstall-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-hy2.sh && chmod +x /root/uninstall-hy2.sh && /root/uninstall-hy2.sh
```

如果系统里没有 `wget`，可以用 `curl`：

```sh
curl -L -o /root/uninstall-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-hy2.sh && chmod +x /root/uninstall-hy2.sh && /root/uninstall-hy2.sh
```

## 功能说明

| 功能 | 说明 |
| --- | --- |
| 自动安装依赖 | Debian / Ubuntu 使用 `apt-get`，Alpine 使用 `apk` |
| 自动获取公网 IP | 从多个公网 IP 接口依次获取 |
| 自动识别架构 | 支持 `x86_64`、`amd64`、`arm64`、`aarch64`、`armv7l` |
| 自动生成端口 | 为 Reality 和 WS 分别推荐随机端口 |
| 支持自定义端口 | 回车使用推荐端口，也可以手动输入端口 |
| 端口校验 | 检查端口格式，并避免使用已占用端口 |
| 自动生成密钥 | 自动生成 UUID、Reality X25519 密钥、Short ID |
| 自动开机自启 | 支持 `systemd` 和 `OpenRC` |
| 保存节点信息 | 保存节点链接，后续可用 `info` 查看 |
| 中文提示 | 安装、报错、输出信息均为中文 |
| HY2 支持 | 支持一键部署 Hysteria2，自签证书，自动输出 `hy2://` 链接 |

## 支持系统

- Debian
- Ubuntu
- Alpine
- 其他带基础命令的精简 Linux 环境

脚本会优先配置服务管理器：

- Debian / Ubuntu：`systemd`
- Alpine：`OpenRC`

如果系统里没有 `systemd` 或 `OpenRC`，脚本会回退到普通后台启动脚本：

```sh
/root/start-xray.sh
```

## 默认配置

### Xray 双节点

| 项目 | 默认值 |
| --- | --- |
| Reality SNI | `www.sony.com` |
| Reality 目标站 | `www.sony.com:443` |
| WS 路径 | `/ws` |
| WS TLS | 不启用，`security=none` |
| 日志级别 | `warning` |

### HY2

| 项目 | 默认值 |
| --- | --- |
| 默认端口 | `8443/UDP` |
| SNI | `bing.com` |
| 伪装站点 | `https://www.bing.com` |
| 证书 | 自签证书 |
| 客户端要求 | 需要开启 `insecure` / 跳过证书验证 |

## 端口建议

安装时你最终选择的两个端口都需要放行：

- `Reality 端口 / TCP`
- `WS 端口 / TCP`

如果是云服务器，请同时确认：

- VPS 厂商控制台安全组已放行
- 系统内防火墙已放行

> [!IMPORTANT]
> Reality 更推荐使用 `443` 端口。使用非 `443` 端口时，Xray 通常可以正常启动，但在部分网络环境下稳定性可能会差一些。

WS 可以使用常见 TCP 端口，例如：

```text
80、8080、8880、2052、2082、2086、2095
```

HY2 需要放行 UDP 端口，例如：

```text
8443/UDP
```

## 常用命令

### 查看 Xray 节点信息

```sh
/root/install-xray-dual-auto.sh info
```

### 查看 HY2 节点信息

```sh
/root/install-hy2.sh info
```

### 强制重新安装 Xray

```sh
/root/install-xray-dual-auto.sh install
```

### 强制重新安装 HY2

```sh
/root/install-hy2.sh install
```

### 测试 Xray 配置

```sh
xray run -test -config /usr/local/etc/xray/config.json
```

### 查看监听端口

Xray：

```sh
ss -tnlp | grep xray
```

HY2：

```sh
ss -unlp | grep hysteria
```

如果没有 `ss`：

```sh
netstat -tunlp | grep xray
```

### 查看日志

访问日志：

```sh
tail -f /var/log/xray-access.log
```

错误日志：

```sh
tail -f /var/log/xray-error.log
```

## 服务管理

### Xray / Debian / Ubuntu

查看状态：

```sh
systemctl status xray --no-pager
```

启动：

```sh
systemctl start xray
```

重启：

```sh
systemctl restart xray
```

停止：

```sh
systemctl stop xray
```

### Xray / Alpine

查看状态：

```sh
rc-service xray status
```

启动：

```sh
rc-service xray start
```

重启：

```sh
rc-service xray restart
```

停止：

```sh
rc-service xray stop
```

### HY2 / Debian / Ubuntu

查看状态：

```sh
systemctl status hysteria-server.service --no-pager -l
```

启动：

```sh
systemctl start hysteria-server.service
```

重启：

```sh
systemctl restart hysteria-server.service
```

停止：

```sh
systemctl stop hysteria-server.service
```

### HY2 / Alpine

查看状态：

```sh
rc-service hysteria status
```

启动：

```sh
rc-service hysteria start
```

重启：

```sh
rc-service hysteria restart
```

停止：

```sh
rc-service hysteria stop
```

## 相关文件

| 文件 | 说明 |
| --- | --- |
| `/usr/local/bin/xray` | Xray 主程序 |
| `/usr/local/etc/xray/config.json` | Xray 配置文件 |
| `/usr/local/etc/xray/node-info.txt` | 节点信息文件 |
| `/root/xray-node-info.txt` | 节点信息备份 |
| `/root/install-xray-dual-auto.sh` | 安装脚本 |
| `/root/uninstall-xray-dual.sh` | 卸载脚本 |
| `/root/start-xray.sh` | 无服务管理器时的启动脚本 |
| `/var/log/xray-access.log` | 访问日志 |
| `/var/log/xray-error.log` | 错误日志 |
| `/var/log/xray.log` | fallback 后台启动日志 |
| `/usr/local/bin/hysteria` | Hysteria2 主程序 |
| `/etc/hysteria/config.yaml` | HY2 配置文件 |
| `/etc/hysteria/node-info.txt` | HY2 节点信息文件 |
| `/root/hy2-node-info.txt` | HY2 节点信息备份 |
| `/root/install-hy2.sh` | HY2 安装脚本 |
| `/root/uninstall-hy2.sh` | HY2 卸载脚本 |
| `/root/start-hy2.sh` | HY2 无服务管理器时的启动脚本 |
| `/var/log/hysteria.log` | HY2 fallback 后台启动日志 |

## 卸载会删除的内容

### Xray 双节点

- `/usr/local/bin/xray`
- `/usr/local/etc/xray`
- `/root/start-xray.sh`
- `/root/xray-node-info.txt`
- `/var/log/xray.log`
- `/var/log/xray-access.log`
- `/var/log/xray-error.log`
- `systemd` 或 `OpenRC` 中的 `xray` 服务定义

### HY2

- `/usr/local/bin/hysteria`
- `/etc/hysteria`
- `/root/start-hy2.sh`
- `/root/hy2-node-info.txt`
- `/var/log/hysteria.log`
- `systemd` 或 `OpenRC` 中的 `hysteria` 服务定义

## 常见问题

### 脚本看起来卡住了

常见原因：

- 正在等待你输入端口
- 机器访问 GitHub 慢
- 小内存机器安装依赖时被系统杀掉

可以先按一次回车，看看是不是在等待端口输入。

### 提示 `curl: not found` 或 `wget: not found`

先手动安装一个下载工具。

Debian / Ubuntu：

```sh
apt-get update
apt-get install -y curl wget
```

Alpine：

```sh
apk update
apk add curl wget
```

### 提示 `Killed`

一般是机器内存太小，安装依赖或解压时被系统杀掉。可以尝试：

- 换内存更大的 VPS
- 关闭其他占内存的进程
- 使用更精简的系统环境

### 提示 `Exec format error`

常见于脚本或 OpenRC 服务文件换行符不正确，尤其是 Windows 手动复制后再粘贴到 Alpine 的场景。

> [!TIP]
> 建议直接从 GitHub 下载最新版脚本，不要手动复制残缺内容。

### 提示 `invalid character 'R' looking for beginning of value`

这是旧版脚本端口输入污染配置文件导致的问题。重新下载最新版脚本后再运行即可。

### `rc-service xray status` 提示 `service 'xray' does not exist`

说明 OpenRC 服务文件没有创建成功，或者之前只是手动运行了 Xray。

重新运行最新版安装脚本即可自动写入：

```sh
/etc/init.d/xray
```

### `xray run -test` 通过，但端口没有监听

先检查服务是否启动：

```sh
ps aux | grep -i xray
ss -tnlp | grep xray
```

重点检查：

- 服务是否真正启动
- 端口是否被占用
- 服务管理器是否写入成功

### `tcping` 通，但客户端延迟显示 `-1`

通常说明端口通了，但协议握手失败。优先检查：

- 节点链接是否复制完整
- Reality 的 `pbk`、`sid`、`sni` 是否正确
- WS 的 `path` 是否是 `/ws`
- 客户端协议类型是否选对

### HY2 服务启动失败，提示 `permission denied`

如果日志里出现：

```text
tls.key: open /etc/hysteria/cert/server.key: permission denied
```

执行：

```sh
chmod 644 /etc/hysteria/cert/server.key
chmod 644 /etc/hysteria/cert/server.crt
systemctl restart hysteria-server.service
```

最新版 HY2 脚本已经自动处理这个权限问题。

### HY2 客户端连不上

优先检查：

- VPS 安全组是否放行 `UDP` 端口
- 系统防火墙是否放行 `UDP` 端口
- 客户端是否开启 `insecure` / 跳过证书验证
- 链接里的端口、密码、SNI 是否复制完整

## 项目说明

- 当前脚本部署的是 `VLESS + Reality` 和 `VLESS + WS`。
- 当前 HY2 脚本部署的是 `Hysteria2`。
- 当前 WS 节点是 `security=none`，不是 `VLESS + WS + TLS`。
- 当前 HY2 使用自签证书，客户端需要开启 `insecure`。
- Reality 使用非 `443` 端口时，部分网络环境下稳定性可能会差一些。
- 本项目不包含域名、证书、CDN 配置。

## 使用提醒

> [!WARNING]
> 请勿将节点信息、UUID、Reality 密钥等敏感信息公开到 Issue、截图或聊天记录中。

- 本项目仅供学习、测试和自用。
- 使用前请确认符合你所在地区的法律法规。
- 使用前请确认符合 VPS 服务商、网络运营商和相关平台的服务条款。

## License

本项目使用 [MIT License](LICENSE)。
