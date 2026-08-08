# Xray / HY2 / Snell 一键安装脚本

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

脚本会自动安装依赖、自动获取公网 IP、自动写入服务自启，并把节点信息保存到 VPS 本机，后续可以随时用 `info` 查看。

> [!IMPORTANT]
> `Snell` 主要适用于 `Surge` 客户端。`Clash`、`Clash Meta`、`Stash` 这类主流客户端通常不支持 Snell。

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
5. 查看已保存的节点信息
6. 卸载节点
```

也支持直接指定类型：

```sh
/root/install.sh reality
/root/install.sh dual
/root/install.sh hy2
/root/install.sh snell
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

### Reality

```sh
/root/install-reality.sh info
```

保存位置：

```text
/usr/local/etc/xray/reality-node-info.txt
/root/reality-node-info.txt
```

### Xray 双节点

```sh
/root/install-xray-dual-auto.sh info
```

保存位置：

```text
/usr/local/etc/xray/node-info.txt
/root/xray-node-info.txt
```

### HY2

```sh
/root/install-hy2.sh info
```

保存位置：

```text
/etc/hysteria/node-info.txt
/root/hy2-node-info.txt
```

### Snell v6

```sh
/root/install-snell.sh info
```

保存位置：

```text
/etc/snell/node-info.txt
/root/snell-node-info.txt
```

## 卸载命令

### 卸载 Reality

```sh
wget -O /root/uninstall-reality.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-reality.sh && chmod +x /root/uninstall-reality.sh && /root/uninstall-reality.sh
```

### 卸载 Xray 双节点

```sh
wget -O /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
```

### 卸载 HY2

```sh
wget -O /root/uninstall-hy2.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-hy2.sh && chmod +x /root/uninstall-hy2.sh && /root/uninstall-hy2.sh
```

### 卸载 Snell v6

```sh
wget -O /root/uninstall-snell.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-snell.sh && chmod +x /root/uninstall-snell.sh && /root/uninstall-snell.sh
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
| 客户端要求 | 需开启 `insecure` |

### Snell v6

| 项目 | 默认值 |
| --- | --- |
| 端口 | `8666/TCP` |
| 模式 | `default` |
| PSK | 自动生成 32 位随机字符串 |
| 客户端 | 推荐 `Surge` |

## Snell v6 说明

当前脚本使用的是官方发布页可下载到的 `Snell v6.0.0rc2`。

脚本会输出一段可直接放进 `Surge` 的配置片段，例如：

```ini
[Proxy]
snell = 1.2.3.4, 8666, psk=你的PSK, version=6, reuse=true
```

安装时可选模式：

- `default`：推荐，启用混淆和加密
- `unshaped`：关闭混淆，只保留加密，性能更高
- `unsafe-raw`：明文转发，只适合内网或其他安全隧道环境

> [!WARNING]
> `unsafe-raw` 不适合公网裸跑。

## 端口放行建议

安装后请确认云厂商安全组和系统防火墙都已放行对应端口：

- `Reality`：`TCP`
- `WS`：`TCP`
- `HY2`：`UDP`
- `Snell`：`TCP`

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

### 查看 Xray 日志

```sh
tail -f /var/log/xray-access.log
tail -f /var/log/xray-error.log
```

## 服务管理

### Debian / Ubuntu

Xray：

```sh
systemctl status xray --no-pager
systemctl restart xray
```

HY2：

```sh
systemctl status hysteria-server.service --no-pager -l
systemctl restart hysteria-server.service
```

Snell：

```sh
systemctl status snell --no-pager -l
systemctl restart snell
```

### Alpine

Xray：

```sh
rc-service xray status
rc-service xray restart
```

HY2：

```sh
rc-service hysteria status
rc-service hysteria restart
```

Snell：

```sh
rc-service snell status
rc-service snell restart
```

## 相关文件

| 文件 | 说明 |
| --- | --- |
| `/usr/local/etc/xray/config.json` | Xray 配置 |
| `/etc/hysteria/config.yaml` | HY2 配置 |
| `/etc/snell/snell-server.conf` | Snell 配置 |
| `/root/install.sh` | 综合脚本 |
| `/root/install-reality.sh` | Reality 安装脚本 |
| `/root/install-xray-dual-auto.sh` | Xray 双节点安装脚本 |
| `/root/install-hy2.sh` | HY2 安装脚本 |
| `/root/install-snell.sh` | Snell 安装脚本 |

## 常见问题

### 1. 脚本看起来卡住了

常见原因：

- 正在等待你输入端口
- 机器访问 GitHub 较慢
- 小内存机器在安装依赖时被系统杀掉

### 2. 提示 `curl: not found` 或 `wget: not found`

先手动安装：

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

一般是内存太小，安装依赖或解压时被系统杀掉。

### 4. 提示 `Exec format error`

常见于脚本换行符不对，尤其是手动复制到 Alpine 时。建议优先从 GitHub 直接下载脚本。

### 5. Snell 用不了

先确认：

- 你用的是 `Surge`
- 端口已放行
- 配置里写了 `version=6`
- 服务已经成功启动

## 使用提醒

> [!WARNING]
> 请不要把 UUID、Reality 公钥、HY2 密码、Snell PSK 这类敏感信息公开发到截图、Issue 或聊天记录里。

- 本项目仅供学习、测试和自用
- 使用前请确认符合当地法律法规
- 使用前请确认符合 VPS 服务商和网络运营商条款

## License

本项目使用 [MIT License](LICENSE)。
