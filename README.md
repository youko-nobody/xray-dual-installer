# Xray / HY2 / Snell / SOCKS5 / MTProto 一键脚本

![Shell](https://img.shields.io/badge/Shell-sh-4EAA25?style=for-the-badge)
![System](https://img.shields.io/badge/System-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=for-the-badge)
![Service](https://img.shields.io/badge/Service-systemd%20%7C%20OpenRC-f97316?style=for-the-badge)
![Language](https://img.shields.io/badge/Prompt-%E4%B8%AD%E6%96%87-e11d48?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-16a34a?style=for-the-badge)

一个中文化的一键安装仓库，用来快速部署以下节点：

- `VLESS + Reality` 单节点
- `VLESS + Reality + VLESS + WS` 双节点
- `Hysteria2 / HY2`
- `Snell v6`
- `SOCKS5`
- `MTProto`

脚本会自动安装依赖、自动获取公网 IP、自动写入服务自启，并把节点信息保存到 VPS 本机，后续可以随时用 `info` 查看。

> [!IMPORTANT]
> `Snell` 主要适用于 `Surge`。`Clash`、`Clash Meta`、`Stash` 这类主流客户端通常不支持 Snell。

> [!IMPORTANT]
> `MTProto` 是 Telegram 专用代理，不是通用代理协议。

## 综合脚本

推荐直接使用综合脚本：

```sh
wget -O /root/install.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install.sh && chmod +x /root/install.sh && /root/install.sh
```

如果系统里没有 `wget`，也可以用：

```sh
curl -L -o /root/install.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install.sh && chmod +x /root/install.sh && /root/install.sh
```

综合脚本菜单包含：

```text
1. VLESS + Reality 单节点
2. VLESS + Reality + VLESS + WS 双节点
3. Hysteria2 / HY2 节点
4. Snell v6 节点
5. SOCKS5 节点
6. MTProto 节点
7. 查看已保存的节点信息
8. 卸载节点
```

也支持直接指定类型：

```sh
/root/install.sh reality
/root/install.sh dual
/root/install.sh hy2
/root/install.sh snell
/root/install.sh socks5
/root/install.sh mtproto
/root/install.sh info
/root/install.sh uninstall
```

## 单独安装命令

### 1. VLESS + Reality 单节点

```sh
wget -O /root/install-reality.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-reality.sh && chmod +x /root/install-reality.sh && /root/install-reality.sh
```

### 2. VLESS + Reality + VLESS + WS

```sh
wget -O /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

### 3. Hysteria2 / HY2

```sh
wget -O /root/install-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-hy2.sh && chmod +x /root/install-hy2.sh && /root/install-hy2.sh
```

### 4. Snell v6

```sh
wget -O /root/install-snell.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-snell.sh && chmod +x /root/install-snell.sh && /root/install-snell.sh
```

### 5. SOCKS5

```sh
wget -O /root/install-socks5.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-socks5.sh && chmod +x /root/install-socks5.sh && /root/install-socks5.sh
```

### 6. MTProto

```sh
wget -O /root/install-mtproto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-mtproto.sh && chmod +x /root/install-mtproto.sh && /root/install-mtproto.sh
```

## 协议说明

| 类型 | 完整名称 | 传输 | 说明 |
| --- | --- | --- | --- |
| Reality 单节点 | `VLESS + TCP + REALITY + XTLS Vision` | TCP | 主力节点方案 |
| 双节点 | `VLESS + TCP + REALITY + XTLS Vision` + `VLESS + WS` | TCP / WS | 同时提供 Reality 和 WS |
| HY2 | `Hysteria2` | UDP | 自签证书方案 |
| Snell | `Snell v6` | TCP | 主要适合 `Surge` |
| SOCKS5 | `SOCKS5 Username/Password` | TCP + UDP | 通用性高，脚本会输出原始链接和 Telegram 识别链接 |
| MTProto | `Telegram MTProto Proxy` | TCP | 主要用于 Telegram |

## 独立部署说明

现在 `Reality` 和 `SOCKS5` 已经拆成独立服务，可以在同一台机器上同时存在，不会再互相覆盖。

对应关系如下：

| 节点 | 独立服务名 | 独立配置文件 |
| --- | --- | --- |
| Reality | `xray-reality` | `/usr/local/etc/xray/reality-config.json` |
| SOCKS5 | `xray-socks5` | `/usr/local/etc/xray/socks5-config.json` |

也就是说，你可以一台机器同时跑：

- `VLESS + Reality`
- `SOCKS5`
- `HY2`
- `Snell`
- `MTProto`

其中只有 `VLESS + Reality + VLESS + WS` 双节点脚本，仍然是它自己单独占用一套 Xray 配置。

## 功能说明

| 功能 | 说明 |
| --- | --- |
| 自动安装依赖 | Debian / Ubuntu 使用 `apt-get`，Alpine 使用 `apk` |
| 自动获取公网 IP | 从多个公网 IP 接口轮询获取 |
| 自动识别架构 | 支持常见 `amd64`、`arm64`、`armv7l` |
| 自动写入自启 | 支持 `systemd` 和 `OpenRC` |
| 保存节点信息 | 安装完成后可随时通过 `info` 查看 |
| 中文提示 | 安装、报错、输出信息均为中文 |
| 卸载脚本 | 各协议都提供独立卸载脚本 |

## 查看节点信息

### 综合查看

```sh
/root/install.sh info
```

### 单独查看

```sh
/root/install-reality.sh info
/root/install-xray-dual-auto.sh info
/root/install-hy2.sh info
/root/install-snell.sh info
/root/install-socks5.sh info
/root/install-mtproto.sh info
```

## 节点信息保存位置

| 类型 | 保存位置 |
| --- | --- |
| Reality | `/usr/local/etc/xray/reality-node-info.txt` |
| 双节点 | `/usr/local/etc/xray/node-info.txt` |
| HY2 | `/etc/hysteria/node-info.txt` |
| Snell v6 | `/etc/snell/node-info.txt` |
| SOCKS5 | `/usr/local/etc/xray/socks5-node-info.txt` |
| MTProto | `/etc/mtproto-proxy/node-info.txt` |

## 卸载命令

### 综合卸载菜单

```sh
/root/install.sh uninstall
```

### 单独卸载

```sh
wget -O /root/uninstall-reality.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-reality.sh && chmod +x /root/uninstall-reality.sh && /root/uninstall-reality.sh
wget -O /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
wget -O /root/uninstall-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-hy2.sh && chmod +x /root/uninstall-hy2.sh && /root/uninstall-hy2.sh
wget -O /root/uninstall-snell.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-snell.sh && chmod +x /root/uninstall-snell.sh && /root/uninstall-snell.sh
wget -O /root/uninstall-socks5.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-socks5.sh && chmod +x /root/uninstall-socks5.sh && /root/uninstall-socks5.sh
wget -O /root/uninstall-mtproto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-mtproto.sh && chmod +x /root/uninstall-mtproto.sh && /root/uninstall-mtproto.sh
```

## 默认配置

### Reality 单节点

| 项目 | 默认值 |
| --- | --- |
| 端口 | `443/TCP` |
| SNI | `www.sony.com` |
| Flow | `xtls-rprx-vision` |

### Xray 双节点

| 项目 | 默认值 |
| --- | --- |
| Reality SNI | `www.sony.com` |
| WS Path | `/ws` |
| 端口 | 安装时输入，直接回车可用随机推荐端口 |

### HY2

| 项目 | 默认值 |
| --- | --- |
| 端口 | `8443/UDP` |
| SNI | `bing.com` |
| 证书 | 自签证书 |

### Snell v6

| 项目 | 默认值 |
| --- | --- |
| 端口 | `8666/TCP` |
| 模式 | `default` |
| PSK | 自动生成 |

### SOCKS5

| 项目 | 默认值 |
| --- | --- |
| 端口 | 回车使用随机推荐端口 |
| 用户名 | 随机推荐，也可手动输入 |
| 密码 | 随机推荐，也可手动输入 |

### MTProto

| 项目 | 默认值 |
| --- | --- |
| 端口 | 回车使用随机推荐端口 |
| 服务端 Secret | 自动生成 32 位十六进制 |
| 客户端 Secret | 自动在服务端 Secret 前加 `dd` 前缀 |

## MTProto 说明

当前脚本使用 Telegram 官方 [MTProxy](https://github.com/TelegramMessenger/MTProxy) 源码构建。

注意：

- 服务端启动参数 `-S` 使用的是纯 32 位十六进制 secret
- Telegram 客户端导入链接使用的是带 `dd` 前缀的 secret
- 也就是：服务端和客户端看到的 secret 不完全一样，这是正常的
- 重新安装 MTProto 时，脚本会先清理旧的节点信息和旧运行残留，再生成新的配置

输出的链接格式为：

```text
tg://proxy?server=你的IP&port=端口&secret=你的Secret
https://t.me/proxy?server=你的IP&port=端口&secret=你的Secret
```

## 端口放行建议

安装后请确认云厂商安全组和系统防火墙都已放行对应端口：

- `Reality`：TCP
- `WS`：TCP
- `HY2`：UDP
- `Snell`：TCP
- `SOCKS5`：TCP
- `MTProto`：TCP

## 常用命令

### 查看 Xray 配置测试

```sh
xray run -test -config /usr/local/etc/xray/config.json
```

### 查看 Xray 监听

```sh
ss -tnlp | grep xray
```

### 查看 HY2 监听

```sh
ss -unlp | grep hysteria
```

### 查看 Snell 监听

```sh
ss -tnlp | grep snell
```

### 查看 MTProto 监听

```sh
ss -tnlp | grep mtproto
```

## 服务管理

### Debian / Ubuntu

```sh
systemctl status xray --no-pager
systemctl status hysteria-server.service --no-pager -l
systemctl status snell --no-pager -l
systemctl status mtproxy --no-pager -l
```

### Alpine

```sh
rc-service xray status
rc-service hysteria status
rc-service snell status
rc-service mtproxy status
```

## 相关文件

| 文件 | 说明 |
| --- | --- |
| `/usr/local/etc/xray/config.json` | Xray 配置 |
| `/etc/hysteria/config.yaml` | HY2 配置 |
| `/etc/snell/snell-server.conf` | Snell 配置 |
| `/etc/mtproto-proxy` | MTProto 配置目录 |
| `/root/install.sh` | 综合脚本 |

## 常见问题

### 1. 脚本看起来卡住了

常见原因：

- 正在等待你输入端口
- 机器访问 GitHub 较慢
- 小内存机器在安装依赖或编译 MTProto 时被系统杀掉

### 2. 提示 `curl: not found` 或 `wget: not found`

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

### 3. 提示 `Killed`

一般是内存太小，安装依赖或编译时被系统杀掉。

### 4. 提示 `Exec format error`

常见于脚本换行符不对，尤其是手动复制到 Alpine 时。建议优先从 GitHub 直接下载脚本。

## 使用提醒

> [!WARNING]
> 请不要把 UUID、Reality 公钥、HY2 密码、Snell PSK、SOCKS5 用户名密码、MTProto Secret 这类敏感信息公开发到截图、Issue 或聊天记录里。

- 本项目仅供学习、测试和自用
- 使用前请确认符合当地法律法规
- 使用前请确认符合 VPS 服务商和网络运营商条款

## License

本项目使用 [MIT License](LICENSE)。
