# Xray 双节点一键脚本

这个仓库提供一份一键脚本，用来部署：

- `VLESS + Reality`
- `VLESS + WS`

脚本会自动完成下面这些事：

- 先安装依赖
- 自动识别服务器公网 IPv4
- 自动识别系统架构
- 为 `Reality` 和 `WS` 各生成一个推荐随机端口
- 直接回车时使用推荐端口
- 自动生成 UUID、Reality 密钥和 Short ID
- 根据系统自动配置 `systemd` 或 `OpenRC` 开机自启

## 支持系统

- Debian / Ubuntu
- Alpine
- 其他带基础命令的精简环境

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

## 一键安装命令

上传到 GitHub 后，把下面命令里的 `你的 GitHub 用户名` 和 `你的仓库名` 改掉即可直接复制运行：

```sh
wget -O /root/install-xray-dual-auto.sh https://raw.githubusercontent.com/你的GitHub用户名/你的仓库名/main/install-xray-dual-auto.sh && chmod +x /root/install-xray-dual-auto.sh && /root/install-xray-dual-auto.sh
```

## 需要放行的端口

安装时你最终选择的两个端口都要在防火墙或安全组里放行：

- `Reality 端口 / TCP`
- `WS 端口 / TCP`

## 脚本输出内容

脚本执行完成后会输出：

- 当前公网 IP
- Reality 节点链接
- WS 节点链接
- 当前服务状态

## 相关文件

- 配置文件：`/usr/local/etc/xray/config.json`
- Xray 程序：`/usr/local/bin/xray`
- 无服务管理器时的启动脚本：`/root/start-xray.sh`

## 说明

- Reality 使用非 `443` 端口时，在某些网络环境下稳定性可能会差一些。
- 这份脚本里的 WS 使用的是 `security=none`。
