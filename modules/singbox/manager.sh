#!/bin/bash
# sing-box 模块 - VPS-play
# 多协议代理节点管理

# 获取脚本目录
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# 加载工具库
source "$VPSPLAY_DIR/utils/env_detect.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/port_manager.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/process_manager.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/network.sh" 2>/dev/null

# ==================== 配置 ====================
SINGBOX_DIR="$HOME/.vps-play/singbox"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONF="$SINGBOX_DIR/config.json"
SINGBOX_LOG="$SINGBOX_DIR/sing-box.log"

# sing-box 版本
SINGBOX_VERSION="1.10.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$SINGBOX_DIR"

# ==================== 初始化 ====================
init_singbox() {
    if [ -z "$ENV_TYPE" ]; then
        detect_environment
    fi
    
    echo -e "${Info} sing-box 工作目录: $SINGBOX_DIR"
    echo -e "${Info} 环境类型: ${Cyan}${ENV_TYPE}${Reset}"
}

# ==================== 下载安装 ====================
download_singbox() {
    echo -e "${Info} 正在下载 sing-box v${SINGBOX_VERSION}..."
    
    local os_type="linux"
    local arch_type="amd64"
    
    case "$OS_TYPE" in
        freebsd) os_type="freebsd" ;;
        linux) os_type="linux" ;;
    esac
    
    case "$ARCH" in
        amd64) arch_type="amd64" ;;
        arm64) arch_type="arm64" ;;
        armv7) arch_type="armv7" ;;
    esac
    
    local download_url="${SINGBOX_REPO}/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-${os_type}-${arch_type}.tar.gz"
    
    echo -e "${Info} 下载地址: $download_url"
    
    cd "$SINGBOX_DIR"
    
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o sing-box.tar.gz
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O sing-box.tar.gz
    else
        echo -e "${Error} 需要 curl 或 wget"
        return 1
    fi
    
    tar -xzf sing-box.tar.gz --strip-components=1
    rm -f sing-box.tar.gz
    chmod +x sing-box
    
    echo -e "${Info} sing-box 下载完成"
}

# ==================== 配置模板 ====================
# 生成 VLESS 配置
generate_vless_config() {
    local port=$1
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 12)")
    
    cat << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "flow": ""
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vless"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
}

# 生成 VMess 配置
generate_vmess_config() {
    local port=$1
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 12)")
    
    cat << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vmess"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
}

# 生成 Trojan 配置
generate_trojan_config() {
    local port=$1
    local password=${2:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)}
    
    cat << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
}

# 生成 Hysteria2 配置
generate_hy2_config() {
    local port=$1
    local password=${2:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)}
    
    cat << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "key_path": "$SINGBOX_DIR/server.key",
        "certificate_path": "$SINGBOX_DIR/server.crt"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
}

# ==================== 安装 ====================
install_singbox() {
    init_singbox
    
    if [ -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 已安装"
        read -p "是否重新安装? [y/N]: " reinstall
        [[ ! $reinstall =~ ^[Yy]$ ]] && return 0
    fi
    
    download_singbox
    
    echo -e ""
    echo -e "${Info} sing-box 安装完成!"
    echo -e "${Info} 版本: $($SINGBOX_BIN version 2>/dev/null | head -1)"
}

# ==================== 创建节点 ====================
create_node() {
    echo -e ""
    echo -e "${Info} 选择节点协议:"
    echo -e " ${Green}1.${Reset}  VLESS + WebSocket"
    echo -e " ${Green}2.${Reset}  VMess + WebSocket"
    echo -e " ${Green}3.${Reset}  Trojan"
    echo -e " ${Green}4.${Reset}  Hysteria2 (UDP)"
    
    read -p "请选择 [1-4]: " proto_choice
    
    # 获取端口
    echo -e ""
    if [ "$ENV_TYPE" = "serv00" ]; then
        echo -e "${Warning} Serv00 环境请输入已通过 devil 添加的端口"
    fi
    
    read -p "请输入端口: " node_port
    
    if [ -z "$node_port" ]; then
        echo -e "${Error} 端口不能为空"
        return 1
    fi
    
    # 生成配置
    case "$proto_choice" in
        1)
            generate_vless_config "$node_port" > "$SINGBOX_CONF"
            proto_name="VLESS"
            ;;
        2)
            generate_vmess_config "$node_port" > "$SINGBOX_CONF"
            proto_name="VMess"
            ;;
        3)
            read -p "Trojan 密码 (留空自动生成): " tr_pass
            generate_trojan_config "$node_port" "$tr_pass" > "$SINGBOX_CONF"
            proto_name="Trojan"
            ;;
        4)
            # 生成自签名证书
            if [ ! -f "$SINGBOX_DIR/server.key" ]; then
                echo -e "${Info} 生成自签名证书..."
                openssl req -x509 -newkey rsa:2048 -keyout "$SINGBOX_DIR/server.key" -out "$SINGBOX_DIR/server.crt" -days 365 -nodes -subj "/CN=www.bing.com" 2>/dev/null
            fi
            read -p "Hysteria2 密码 (留空自动生成): " hy2_pass
            generate_hy2_config "$node_port" "$hy2_pass" > "$SINGBOX_CONF"
            proto_name="Hysteria2"
            ;;
        *)
            echo -e "${Error} 无效选择"
            return 1
            ;;
    esac
    
    echo -e ""
    echo -e "${Info} ${proto_name} 节点配置已创建"
    echo -e "${Info} 配置文件: $SINGBOX_CONF"
    
    # 显示节点信息
    show_node_info
}

# ==================== 显示节点信息 ====================
show_node_info() {
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Warning} 配置文件不存在"
        return 1
    fi
    
    echo -e ""
    echo -e "${Green}==================== 节点信息 ====================${Reset}"
    
    local port=$(grep -o '"listen_port":[0-9]*' "$SINGBOX_CONF" | cut -d: -f2)
    local proto=$(grep -o '"type":"[^"]*"' "$SINGBOX_CONF" | head -1 | cut -d'"' -f4)
    local uuid=$(grep -o '"uuid":"[^"]*"' "$SINGBOX_CONF" | cut -d'"' -f4)
    local password=$(grep -o '"password":"[^"]*"' "$SINGBOX_CONF" | cut -d'"' -f4)
    
    echo -e " 协议:   ${Cyan}${proto}${Reset}"
    echo -e " 端口:   ${Cyan}${port}${Reset}"
    echo -e " 地址:   ${Cyan}${PUBLIC_IP:-YOUR_IP}${Reset}"
    
    if [ -n "$uuid" ]; then
        echo -e " UUID:   ${Cyan}${uuid}${Reset}"
    fi
    
    if [ -n "$password" ]; then
        echo -e " 密码:   ${Cyan}${password}${Reset}"
    fi
    
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 启动/停止 ====================
start_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Error} sing-box 未安装"
        return 1
    fi
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Error} 配置文件不存在，请先创建节点"
        return 1
    fi
    
    echo -e "${Info} 启动 sing-box..."
    start_process "singbox" "$SINGBOX_BIN run -c $SINGBOX_CONF" "$SINGBOX_DIR"
    
    sleep 2
    if status_process "singbox" &>/dev/null; then
        echo -e "${Info} sing-box 启动成功"
        show_node_info
    else
        echo -e "${Error} sing-box 启动失败"
    fi
}

stop_singbox() {
    echo -e "${Info} 停止 sing-box..."
    stop_process "singbox"
}

restart_singbox() {
    stop_singbox
    sleep 1
    start_singbox
}

status_singbox() {
    echo -e "${Info} sing-box 状态:"
    status_process "singbox"
}

# ==================== 卸载 ====================
uninstall_singbox() {
    echo -e "${Warning} 确定要卸载 sing-box? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    rm -rf "$SINGBOX_DIR"
    echo -e "${Info} sing-box 已卸载"
}

# ==================== 主菜单 ====================
show_singbox_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦╔╗╔╔═╗   ╔╗ ╔═╗═╗ ╦
    ╚═╗║║║║║ ╦───╠╩╗║ ║╔╩╦╝
    ╚═╝╩╝╚╝╚═╝   ╚═╝╚═╝╩ ╚═
    多协议代理节点
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if [ -f "$SINGBOX_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "singbox" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== sing-box 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 sing-box"
        echo -e " ${Green}2.${Reset}  卸载 sing-box"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  创建节点"
        echo -e " ${Green}4.${Reset}  查看节点信息"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}5.${Reset}  启动"
        echo -e " ${Green}6.${Reset}  停止"
        echo -e " ${Green}7.${Reset}  重启"
        echo -e " ${Green}8.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-8]: " choice
        
        case "$choice" in
            1) install_singbox ;;
            2) uninstall_singbox ;;
            3) create_node ;;
            4) show_node_info ;;
            5) start_singbox ;;
            6) stop_singbox ;;
            7) restart_singbox ;;
            8) status_singbox ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
main() {
    init_singbox
    show_singbox_menu
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
