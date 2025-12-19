#!/bin/bash
# FRPC 模块 - VPS-play
# 内网穿透客户端管理

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/frpc"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"

# ==================== 颜色定义 ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ==================== 配置 ====================
FRPC_DIR="$HOME/.vps-play/frpc"
FRPC_BIN="$FRPC_DIR/frpc"
FRPC_CONF="$FRPC_DIR/frpc.toml"
FRPC_LOG="$FRPC_DIR/frpc.log"
FRPC_VERSION="0.61.1"

mkdir -p "$FRPC_DIR"

# ==================== 下载安装 ====================
download_frpc() {
    echo -e "${Info} 正在下载 FRPC v${FRPC_VERSION}..."
    
    local os_type="linux"
    local arch_type="amd64"
    
    case "$OS_TYPE" in
        freebsd) os_type="freebsd" ;;
        linux) os_type="linux" ;;
    esac
    
    case "$ARCH" in
        amd64) arch_type="amd64" ;;
        arm64) arch_type="arm64" ;;
        armv7) arch_type="arm" ;;
    esac
    
    local download_url="https://github.com/fatedier/frp/releases/download/v${FRPC_VERSION}/frp_${FRPC_VERSION}_${os_type}_${arch_type}.tar.gz"
    
    cd "$FRPC_DIR"
    
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o frpc.tar.gz
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O frpc.tar.gz
    fi
    
    tar -xzf frpc.tar.gz --strip-components=1
    rm -f frpc.tar.gz frps* *.md LICENSE
    chmod +x frpc
    
    echo -e "${Info} FRPC 下载完成"
}

# ==================== 配置管理 ====================
create_config() {
    echo -e ""
    read -p "FRPS 服务器地址: " server_addr
    read -p "FRPS 服务器端口 [7000]: " server_port
    server_port=${server_port:-7000}
    read -p "连接密钥 (Token): " auth_token
    
    cat > "$FRPC_CONF" << EOF
serverAddr = "$server_addr"
serverPort = $server_port
auth.token = "$auth_token"

# 示例隧道配置
# [[proxies]]
# name = "ssh"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 22
# remotePort = 6000
EOF
    
    echo -e "${Info} 基础配置已创建: $FRPC_CONF"
}

add_tunnel() {
    echo -e ""
    echo -e "${Info} 添加隧道配置"
    
    read -p "隧道名称: " tunnel_name
    echo -e "隧道类型: "
    echo -e " ${Green}1.${Reset} TCP"
    echo -e " ${Green}2.${Reset} UDP"
    echo -e " ${Green}3.${Reset} HTTP"
    echo -e " ${Green}4.${Reset} HTTPS"
    read -p "请选择 [1-4]: " tunnel_type
    
    read -p "本地IP [127.0.0.1]: " local_ip
    local_ip=${local_ip:-127.0.0.1}
    read -p "本地端口: " local_port
    
    case "$tunnel_type" in
        1)
            read -p "远程端口: " remote_port
            cat >> "$FRPC_CONF" << EOF

[[proxies]]
name = "$tunnel_name"
type = "tcp"
localIP = "$local_ip"
localPort = $local_port
remotePort = $remote_port
EOF
            ;;
        2)
            read -p "远程端口: " remote_port
            cat >> "$FRPC_CONF" << EOF

[[proxies]]
name = "$tunnel_name"
type = "udp"
localIP = "$local_ip"
localPort = $local_port
remotePort = $remote_port
EOF
            ;;
        3)
            read -p "自定义域名: " custom_domain
            cat >> "$FRPC_CONF" << EOF

[[proxies]]
name = "$tunnel_name"
type = "http"
localIP = "$local_ip"
localPort = $local_port
customDomains = ["$custom_domain"]
EOF
            ;;
        4)
            read -p "自定义域名: " custom_domain
            cat >> "$FRPC_CONF" << EOF

[[proxies]]
name = "$tunnel_name"
type = "https"
localIP = "$local_ip"
localPort = $local_port
customDomains = ["$custom_domain"]
EOF
            ;;
    esac
    
    echo -e "${Info} 隧道 $tunnel_name 已添加"
}

show_config() {
    if [ -f "$FRPC_CONF" ]; then
        echo -e "${Info} 当前配置:"
        echo -e "${Cyan}========================================${Reset}"
        cat "$FRPC_CONF"
        echo -e "${Cyan}========================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

# ==================== 服务管理 ====================
start_frpc() {
    if [ ! -f "$FRPC_BIN" ]; then
        echo -e "${Error} FRPC 未安装"
        return 1
    fi
    
    if [ ! -f "$FRPC_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 FRPC..."
    start_process "frpc" "$FRPC_BIN -c $FRPC_CONF" "$FRPC_DIR"
}

stop_frpc() {
    echo -e "${Info} 停止 FRPC..."
    stop_process "frpc"
}

restart_frpc() {
    stop_frpc
    sleep 1
    start_frpc
}

status_frpc() {
    status_process "frpc"
}

# ==================== 主菜单 ====================
show_frpc_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦═╗╔═╗╔═╗
    ╠╣ ╠╦╝╠═╝║  
    ╚  ╩╚═╩  ╚═╝
    内网穿透客户端
EOF
        echo -e "${Reset}"
        
        if [ -f "$FRPC_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "frpc" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== FRPC 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 FRPC"
        echo -e " ${Green}2.${Reset}  卸载 FRPC"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  创建配置"
        echo -e " ${Green}4.${Reset}  添加隧道"
        echo -e " ${Green}5.${Reset}  查看配置"
        echo -e " ${Green}6.${Reset}  编辑配置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  启动"
        echo -e " ${Green}8.${Reset}  停止"
        echo -e " ${Green}9.${Reset}  重启"
        echo -e " ${Green}10.${Reset} 查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-10]: " choice
        
        case "$choice" in
            1) download_frpc ;;
            2) stop_frpc; rm -rf "$FRPC_DIR"; echo -e "${Info} 已卸载" ;;
            3) create_config ;;
            4) add_tunnel ;;
            5) show_config ;;
            6) ${EDITOR:-vi} "$FRPC_CONF" ;;
            7) start_frpc ;;
            8) stop_frpc ;;
            9) restart_frpc ;;
            10) status_frpc ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_frpc_menu
fi
