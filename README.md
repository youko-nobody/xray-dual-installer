# Xray / HY2 / Snell / SOCKS5 / MTProto / AnyTLS / SS2022 一键脚本

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
- `AnyTLS`
- `Shadowsocks 2022 / SS2022`

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
[ 节点安装 ]
 1. VLESS + Reality 单节点
 2. VLESS + Reality + VLESS + WS 双节点
 3. Hysteria2 / HY2 节点
 4. Snell v6 节点
 5. SOCKS5 节点
 6. MTProto 节点
 7. AnyTLS 节点
 8. Shadowsocks 2022 节点

[ 节点管理 ]
 9. 查看已保存的节点信息
10. 卸载节点
11. 退出
```

也支持直接指定类型：

```sh
/root/install.sh reality
/root/install.sh dual
/root/install.sh hy2
/root/install.sh snell
/root/install.sh socks5
/root/install.sh mtproto
/root/install.sh anytls
/root/install.sh ss2022
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

### 7. AnyTLS

```sh
wget -O /root/install-anytls.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-anytls.sh && chmod +x /root/install-anytls.sh && /root/install-anytls.sh
```

### 8. Shadowsocks 2022 / SS2022

```sh
wget -O /root/install-ss2022.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-ss2022.sh && chmod +x /root/install-ss2022.sh && /root/install-ss2022.sh
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
| AnyTLS | `AnyTLS over TLS` | TCP，支持 UDP over TCP | 使用独立 sing-box 服务，不依赖 Xray-core |
| SS2022 | `Shadowsocks 2022` | TCP + UDP | 使用独立 sing-box 服务和固定长度 Base64 密钥 |

> [!IMPORTANT]
> Xray-core 当前不支持 AnyTLS。本项目通过独立的 `sing-box-anytls` 服务部署 AnyTLS；SS2022 使用另一个独立的 `sing-box-ss2022` 服务，因此二者可以与现有 Xray 节点共存。

## 独立部署说明

现在 `Reality`、`Xray 双节点`、`SOCKS5`、`AnyTLS` 和 `SS2022` 都使用独立服务及配置，可以在同一台机器上同时存在，不会互相覆盖；部署时仍需保证监听端口不冲突。

对应关系如下：

| 节点 | 独立服务名 | 独立配置文件 |
| --- | --- | --- |
| Reality | `xray-reality` | `/usr/local/etc/xray/reality-config.json` |
| Xray 双节点 | `xray` | `/usr/local/etc/xray/config.json` |
| SOCKS5 | `xray-socks5` | `/usr/local/etc/xray/socks5-config.json` |
| AnyTLS | `sing-box-anytls` | `/etc/sing-box-anytls/config.json` |
| SS2022 | `sing-box-ss2022` | `/etc/sing-box-ss2022/config.json` |

也就是说，你可以一台机器同时跑：

- `VLESS + Reality`
- `SOCKS5`
- `HY2`
- `Snell`
- `MTProto`
- `AnyTLS`
- `SS2022`

其中 `Reality`、`Xray 双节点` 和 `SOCKS5` 共享 `/usr/local/bin/xray` 二进制，但分别使用 `xray-reality`、`xray`、`xray-socks5` 服务以及各自的配置文件。

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
/root/install-anytls.sh info
/root/install-ss2022.sh info
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
| AnyTLS | `/etc/sing-box-anytls/node-info.txt` |
| SS2022 | `/etc/sing-box-ss2022/node-info.txt` |

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
wget -O /root/uninstall-anytls.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-anytls.sh && chmod +x /root/uninstall-anytls.sh && /root/uninstall-anytls.sh
wget -O /root/uninstall-ss2022.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-ss2022.sh && chmod +x /root/uninstall-ss2022.sh && /root/uninstall-ss2022.sh
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

### AnyTLS

| 项目 | 默认值 |
| --- | --- |
| 端口 | `443/TCP` 空闲时推荐 443，否则推荐随机端口 |
| 密码 | 自动生成 32 位十六进制，也可手动输入 |
| 内核 | 最新稳定版 `sing-box`，最低要求 `1.14` |
| 证书 | 自动 ACME、已有证书或自签证书 |

### Shadowsocks 2022 / SS2022

| 项目 | 默认值 |
| --- | --- |
| 端口 | `20000–39999` 随机空闲高位端口，可手动输入 |
| 加密方式 | `2022-blake3-aes-128-gcm` |
| 密钥 | 自动生成 16 或 32 字节随机值并进行 Base64 编码 |
| 传输 | TCP + UDP 使用相同端口 |
| 内核 | 最新稳定版 `sing-box`，最低要求 `1.12` |

## MTProto 说明

当前脚本使用 Telegram 官方 [MTProxy](https://github.com/TelegramMessenger/MTProxy) 源码构建。

注意：

- 服务端启动参数 `-S` 使用的是纯 32 位十六进制 secret
- Telegram 客户端导入链接使用的是带 `dd` 前缀的 secret
- 也就是：服务端和客户端看到的 secret 不完全一样，这是正常的
- 重新安装 MTProto 时，新运行数据和服务配置通过启动检查后才会生效；失败会恢复旧服务

输出的链接格式为：

```text
tg://proxy?server=你的IP&port=端口&secret=你的Secret
https://t.me/proxy?server=你的IP&port=端口&secret=你的Secret
```

## AnyTLS 证书与客户端说明

安装时可以选择：

1. 自动申请 ACME 证书：推荐，需要域名直接解析到当前 VPS，并确保 TCP 80 未被占用。
2. 使用已有证书：输入证书完整链和私钥路径，脚本会检查格式、有效期及私钥是否匹配。
3. 生成自签证书：不需要域名，但客户端必须开启 `insecure` / 跳过证书验证。

> [!WARNING]
> 自签模式生成的分享链接包含 `insecure=1`。这适合快速测试，但不能防止 TLS 中间人攻击，长期使用建议改为可信证书。

常见客户端兼容情况：

- sing-box `1.12+`
- Mihomo 新版本
- Shadowrocket `2.2.65+`
- 新版 Stash、Loon

仅包含 Xray-core 的客户端不能连接 AnyTLS。分享链接采用 AnyTLS 官方 URI 格式：

```text
anytls://密码@服务器地址:端口/?sni=域名#节点名称
```

## SS2022 加密方式与客户端说明

安装时可以选择：

1. `2022-blake3-aes-128-gcm`：默认，使用 16 字节 Base64 密钥，兼容性最好。
2. `2022-blake3-aes-256-gcm`：使用 32 字节 Base64 密钥。
3. `2022-blake3-chacha20-poly1305`：使用 32 字节 Base64 密钥，Surge 不支持。

SS2022 密钥不是普通密码，脚本会生成随机密钥并验证 Base64 解码后的长度。节点信息会保存标准 SIP002 分享链接：

```text
ss://Base64URL(加密方式:密钥)@服务器地址:端口#节点名称
```

对于 Surge，脚本会在 AES-128 和 AES-256 模式下额外输出：

```ini
[Proxy]
SS2022-端口 = ss, 服务器地址, 端口, encrypt-method=2022-blake3-aes-128-gcm, password=Base64密钥, udp-relay=true
```

使用前请确认客户端支持所选 SS2022 加密方式。旧版 Shadowsocks 客户端即使支持传统 AEAD，也不一定支持 Shadowsocks 2022。

## 端口放行建议

安装后请确认云厂商安全组和系统防火墙都已放行对应端口：

- `Reality`：TCP
- `WS`：TCP
- `HY2`：UDP
- `Snell`：TCP
- `SOCKS5`：TCP + UDP
- `MTProto`：TCP
- `AnyTLS`：TCP；自动 ACME 模式还需要 TCP 80
- `SS2022`：TCP + UDP，二者使用同一个端口

## 常用命令

### 查看 Xray 配置测试

```sh
/usr/local/bin/xray run -test -config /usr/local/etc/xray/reality-config.json
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
/usr/local/bin/xray run -test -config /usr/local/etc/xray/socks5-config.json
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

### 检查 AnyTLS 配置和监听

```sh
/usr/local/bin/sing-box-anytls check -c /etc/sing-box-anytls/config.json
ss -tnlp | grep sing-box-anytls
```

### 检查 SS2022 配置和监听

```sh
/usr/local/bin/sing-box-ss2022 check -c /etc/sing-box-ss2022/config.json
ss -lntp | grep sing-box-ss2022
ss -lnup | grep sing-box-ss2022
```

## 服务管理

### Debian / Ubuntu

```sh
systemctl status xray-reality --no-pager -l
systemctl status xray --no-pager
systemctl status xray-socks5 --no-pager -l
systemctl status hysteria-server.service --no-pager -l
systemctl status snell --no-pager -l
systemctl status mtproxy --no-pager -l
systemctl status sing-box-anytls --no-pager -l
systemctl status sing-box-ss2022 --no-pager -l
```

### Alpine

```sh
rc-service xray-reality status
rc-service xray status
rc-service xray-socks5 status
rc-service hysteria status
rc-service snell status
rc-service mtproxy status
rc-service sing-box-anytls status
rc-service sing-box-ss2022 status
```

## 相关文件

| 文件 | 说明 |
| --- | --- |
| `/usr/local/etc/xray/reality-config.json` | Reality 单节点配置，服务名 `xray-reality` |
| `/usr/local/etc/xray/config.json` | Xray 双节点配置，服务名 `xray` |
| `/usr/local/etc/xray/socks5-config.json` | SOCKS5 配置，服务名 `xray-socks5` |
| `/etc/hysteria/config.yaml` | HY2 配置 |
| `/etc/snell/snell-server.conf` | Snell 配置 |
| `/etc/mtproto-proxy` | MTProto 配置目录 |
| `/etc/sing-box-anytls/config.json` | AnyTLS 配置 |
| `/etc/sing-box-anytls/node-info.txt` | AnyTLS 节点信息 |
| `/etc/sing-box-ss2022/config.json` | SS2022 配置 |
| `/etc/sing-box-ss2022/node-info.txt` | SS2022 节点信息 |
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

### 5. AnyTLS 自动证书申请失败

请确认：

- 域名的 A / AAAA 记录直接指向当前 VPS
- 域名没有开启普通 CDN 代理
- 云安全组和系统防火墙已放行 TCP 80
- TCP 80 没有被 Nginx、Caddy 或其他程序占用

如果 TCP 80 必须由其他服务占用，请选择“使用已有证书”模式。

## 使用提醒

> [!WARNING]
> 请不要把 UUID、Reality 公钥、HY2 密码、Snell PSK、SOCKS5 用户名密码、MTProto Secret、AnyTLS 密码、SS2022 密钥这类敏感信息公开发到截图、Issue 或聊天记录里。

- 本项目仅供学习、测试和自用
- 使用前请确认符合当地法律法规
- 使用前请确认符合 VPS 服务商和网络运营商条款

## License

本项目使用 [MIT License](LICENSE)。
