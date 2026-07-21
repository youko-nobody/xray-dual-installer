# Xray 双节点一键脚本

这个仓库提供一份一键脚本，用来部署：

- `VLESS + Reality`
- `VLESS + WS`

适合想快速在 `Debian / Ubuntu / Alpine` 上完成双节点部署的场景。

## 一键安装命令

直接复制执行：

```sh
wget -O /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

如果系统里暂时没有 `wget`，也可以用：

```sh
curl -L -o /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

## 一键卸载命令

直接复制执行：

```sh
wget -O /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
```

如果系统里暂时没有 `wget`，也可以用：

```sh
curl -L -o /root/uninstall-xray-dual.sh https://raw.githubusercontent.com/youko-nobody/xray-dual-installer/main/uninstall-xray-dual.sh && chmod +x /root/uninstall-xray-dual.sh && /root/uninstall-xray-dual.sh
```

脚本会自动完成下面这些事：

- 先安装依赖
- 自动识别服务器公网 IPv4
- 自动识别系统架构
- 为 `Reality` 和 `WS` 各生成一个推荐随机端口
- 直接回车时使用推荐端口
- 自动生成 UUID、Reality 密钥和 Short ID
- 根据系统自动配置 `systemd` 或 `OpenRC` 开机自启
- 自动保存节点信息，后续可直接查看

## 支持系统

- Debian / Ubuntu
- Alpine
- 其他带基础命令的精简环境

## 安装前建议

正式执行前，建议先确认下面几项：

- 使用 `root` 账号执行脚本
- VPS 安全组 / 防火墙已放行你要使用的 TCP 端口
- 机器可以正常访问 GitHub
- 机器本身还有可用内存和磁盘

如果是特别小的 NAT 机器或极低内存机器，安装依赖时被系统直接 `Killed`，通常不是脚本卡住，而是内存不够。

如果系统里没有 `systemd` 或 `OpenRC`，脚本会回退到：

```sh
/root/start-xray.sh
```

## 固定配置

- Reality 目标站 / SNI：`www.sony.com`
- WS 路径：`/ws`

## 交互方式

执行脚本时，会自动推荐两个随机端口：

- 一个给 Reality
- 一个给 WS

如果你直接按回车，就使用推荐值；如果你想自定义端口，直接输入新端口即可。

## 需要放行的端口

安装时你最终选择的两个端口都要在防火墙或安全组里放行：

- `Reality 端口 / TCP`
- `WS 端口 / TCP`

如果是云服务器，还要同时确认：

- VPS 厂商控制台安全组已放行
- 系统内防火墙已放行

## 推荐端口说明

- `Reality` 更推荐使用 `443`
- `WS` 可以使用其他常见 TCP 端口，比如 `80`、`8080`、`8880`、`2052`、`2082`、`2086`、`2095`，或你自己的自定义端口

如果你把 `Reality` 放在非 `443` 端口，Xray 自身通常可以启动，但在部分网络环境下稳定性可能会差一些。

## 脚本输出内容

脚本执行完成后会输出：

- 当前公网 IP
- Reality 节点链接
- WS 节点链接
- 当前服务状态

如果你第一次没有复制，后续可以直接运行：

```sh
/root/install-xray-dual-auto.sh info
```

## 相关文件

- 配置文件：`/usr/local/etc/xray/config.json`
- Xray 程序：`/usr/local/bin/xray`
- 无服务管理器时的启动脚本：`/root/start-xray.sh`

## 卸载会删除的内容

- `/usr/local/bin/xray`
- `/usr/local/etc/xray`
- `/root/start-xray.sh`
- `/var/log/xray.log`
- `/var/log/xray-access.log`
- `/var/log/xray-error.log`
- `systemd` 或 `OpenRC` 中的 `xray` 服务定义

## 常用命令

### 1. 检查 Xray 是否启动

Debian / Ubuntu：

```sh
systemctl status xray --no-pager
```

Alpine：

```sh
rc-service xray status
```

通用检查监听端口：

```sh
ss -tnlp | grep -E ':443|:81|:85'
```

如果系统里没有 `ss`，也可以用：

```sh
netstat -tunlp | grep xray
```

### 2. 启动 / 重启 Xray

Debian / Ubuntu：

```sh
systemctl restart xray
```

Alpine：

```sh
rc-service xray restart
```

如果系统里没有服务管理器，可以手动执行：

```sh
/root/start-xray.sh
```

### 3. 查看 Xray 日志

访问日志：

```sh
tail -f /var/log/xray-access.log
```

错误日志：

```sh
tail -f /var/log/xray-error.log
```

### 4. 测试配置文件是否正确

```sh
xray run -test -config /usr/local/etc/xray/config.json
```

## 常见问题排查

### 1. 脚本看起来卡住了

常见原因：

- 正在等待你输入端口
- 机器访问 GitHub 慢
- 小内存机器安装依赖时被系统杀掉

可以先按一次回车，看看是不是在等端口输入。

### 2. 提示 `curl: not found` 或 `wget: not found`

先手动安装一个下载工具再执行脚本。

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

### 3. 提示 `invalid character 'R' looking for beginning of value`

这是旧版本脚本里端口输入污染配置文件导致的问题。重新拉取本仓库最新版脚本后再运行即可。

### 4. 提示 `Exec format error`

这类报错常见于脚本或服务文件换行符不对，尤其是 Windows 编辑后上传到 Alpine / OpenRC 的场景。

直接重新从本仓库下载最新版脚本，不要手动复制一段残缺内容。

### 5. `rc-service xray status` 提示 `service 'xray' does not exist`

这说明 OpenRC 服务文件没有创建成功，或者你之前只是临时手动运行了 `xray run`。

重新运行最新版安装脚本，脚本会自动写入：

```sh
/etc/init.d/xray
```

然后再执行：

```sh
rc-service xray restart
rc-service xray status
```

### 6. `xray run -test` 通过了，但端口没有监听

先检查服务是否真的启动：

```sh
ps aux | grep -i xray
ss -tnlp | grep xray
```

如果配置正确但没有监听，优先检查：

- 服务是否没启动
- 端口是否被别的程序占用
- 服务管理器是否写入成功

### 7. 可以 `tcping` 通，但客户端延迟显示 `-1`

通常说明端口通了，但协议握手没有成功。优先检查：

- 节点链接参数是否填错
- `Reality` 的 `pbk`、`sid`、`sni` 是否和服务端一致
- `WS` 的 `path` 是否一致
- 客户端使用的协议类型是否选对

### 8. 日志文件不存在

先确认你运行的是本仓库最新版脚本。当前版本会自动创建：

- `/var/log/xray-access.log`
- `/var/log/xray-error.log`

如果文件存在但没有内容，说明当前还没有新的连接进入，或者日志级别较低。

## 说明

- Reality 使用非 `443` 端口时，在某些网络环境下稳定性可能会差一些。
- 这份脚本里的 WS 使用的是 `security=none`。
- 当前脚本部署的是 `VLESS + WS`，不是 `VLESS + WS + TLS`。

## 使用提醒

- 本项目仅供学习、测试和自用。
- 使用前请确认符合你所在地区的法律法规。
- 使用前请确认符合 VPS 服务商、网络运营商和相关平台的服务条款。
