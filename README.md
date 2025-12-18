# VPS-play

> 通用 VPS 管理工具，支持普通VPS、NAT VPS、FreeBSD、Serv00/Hostuno

## ✨ 特性

- 🌐 **多环境支持**: 自动识别并适配不同VPS环境
  - 普通VPS (有root权限)
  - NAT VPS (端口映射)
  - FreeBSD 系统
  - Serv00/Hostuno 特殊环境
  
- 🛠️ **统一管理**: 一个脚本管理所有服务
  - sing-box 节点
  - GOST 流量中转
  - X-UI 可视化面板
  - FRPC 内网穿透
  - Cloudflared 隧道
  - 哪吒监控

- 🔧 **智能端口管理**: 自动适配端口管理方式
  - devil (Serv00/Hostuno)
  - iptables (VPS)
  - socat (NAT环境)
  - 直接绑定

- 🔄 **保活功能**: 多种保活方式
  - 本地进程保活
  - 远程SSH复活
  - Cron定时任务
  - systemd 服务

## 📦 支持的环境

| 环境类型 | 权限 | 端口管理 | 服务管理 | 状态 |
|---------|------|---------|---------|------|
| 普通VPS | root | direct/iptables | systemd | ✅ 支持 |
| NAT VPS | root/limited | iptables/socat | systemd/cron | ✅ 支持 |
| FreeBSD | root | direct | rc.d/cron | ✅ 支持 |
| Serv00/Hostuno | limited | devil | cron | ✅ 支持 |

## 🚀 快速开始

### 一键安装

```bash
# 一键安装 (推荐)
curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash

# 或使用 wget
wget -qO- https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash

# 安装完成后运行
vps-play
```

### 基本使用

```bash
# 启动主菜单
./start.sh

# 环境检测
./utils/env_detect.sh

# 端口管理
./utils/port_manager.sh add 12345 tcp
./utils/port_manager.sh list
./utils/port_manager.sh del 12345
```

## 📖 功能模块

### 1. sing-box 节点

支持多种协议的代理节点：
- VMess
- VLESS
- Trojan
- Hysteria2
- TUIC

### 2. GOST 流量中转

强大的流量中转工具：
- 多协议支持
- 智能端口分配
- 自动配置生成

### 3. X-UI 面板

可视化管理面板：
- Web界面管理
- 多用户支持
- 流量统计

### 4. FRPC 内网穿透

内网穿透客户端：
- 多隧道支持
- 自动重连
- 配置持久化

### 5. Cloudflared 隧道

Cloudflare Tunnel：
- 无需公网IP
- HTTPS支持
- 免费使用

### 6. 哪吒监控

服务器监控：
- 实时监控
- 告警通知
- 多服务器管理

## 🔧 系统工具

### 环境检测

自动检测并识别：
- 操作系统类型
- 架构信息
- 权限级别
- 网络环境（公网/NAT）
- 可用服务（systemd/devil）

### 端口管理

统一的端口管理接口：
- 自动选择最佳管理方式
- 支持TCP/UDP协议
- 端口可用性检查
- 随机端口分配

### 保活设置

多种保活方案：
- 进程监控
- 定时重启
- 远程复活
- 心跳检测

## 📁 项目结构

```
VPS-play/
├── start.sh              # 主入口脚本
├── install.sh            # 一键安装脚本
├── utils/                # 工具库
│   ├── env_detect.sh     # 环境检测
│   ├── port_manager.sh   # 端口管理
│   ├── process_manager.sh # 进程管理
│   └── network.sh        # 网络工具
├── modules/              # 功能模块
│   ├── singbox/          # sing-box
│   ├── gost/             # GOST
│   ├── xui/              # X-UI
│   ├── frpc/             # FRPC
│   ├── cloudflared/      # Cloudflared
│   └── nezha/            # 哪吒监控
├── keepalive/            # 保活脚本
│   ├── local_keepalive.sh
│   └── remote_revive.sh
├── config/               # 配置文件
└── README.md
```

## 🔄 更新日志

### v1.0.0 (2025-12-19)

- ✨ 初始版本发布
- ✅ 环境自动检测
- ✅ 统一端口管理
- ✅ 基础框架搭建
- 🚧 各功能模块开发中

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 🙏 致谢

本项目参考了以下优秀项目：
- [serv00-play](https://github.com/frankiejun/serv00-play)
- [GostXray](https://github.com/hxzlplp7/GostXray)
- [serv00-xui](https://github.com/hxzlplp7/serv00-xui)

## 📞 联系方式

- GitHub Issues: [提交问题](https://github.com/hxzlplp7/vps-play/issues)
- Telegram: [加入讨论](https://t.me/YOUR_GROUP)

---

⭐ 如果这个项目对你有帮助，请给个 Star！
