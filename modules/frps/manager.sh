#!/bin/bash
# FRPS 模块 - VPS-play
# 内网穿透服务端管理

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/frps"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"

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
FRPS_DIR="$HOME/.vps-play/frps"
FRPS_BIN="$FRPS_DIR/frps"
FRPS_CONF="$FRPS_DIR/frps.toml"
FRPS_LOG="$FRPS_DIR/frps.log"
FRPS_VERSION="0.61.1"

mkdir -p "$FRPS_DIR"

# ==================== 下载安装 ====================
download_frps() {
    echo -e "${Info} 正在下载 FRPS v${FRPS_VERSION}..."
    
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
    
    local download_url="https://github.com/fatedier/frp/releases/download/v${FRPS_VERSION}/frp_${FRPS_VERSION}_${os_type}_${arch_type}.tar.gz"
    
    cd "$FRPS_DIR"
    
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o frps.tar.gz
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O frps.tar.gz
    fi
    
    tar -xzf frps.tar.gz --strip-components=1
    rm -f frps.tar.gz frpc* *.md LICENSE
    chmod +x frps
    
    echo -e "${Info} FRPS 下载完成"
}

# ==================== 配置管理 ====================
create_config() {
    echo -e ""
    echo -e "${Info} 配置 FRPS 服务端"
    
    # 获取端口
    read -p "绑定端口 [7000]: " bind_port
    bind_port=${bind_port:-7000}
    
    read -p "Dashboard 端口 [7500]: " dashboard_port
    dashboard_port=${dashboard_port:-7500}
    
    read -p "Dashboard 用户名 [admin]: " dashboard_user
    dashboard_user=${dashboard_user:-admin}
    
    read -p "Dashboard 密码 [admin]: " dashboard_pwd
    dashboard_pwd=${dashboard_pwd:-admin}
    
    read -p "认证 Token (留空自动生成): " auth_token
    if [ -z "$auth_token" ]; then
        auth_token=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    fi
    
    read -p "HTTP 代理端口 [80, 留空不启用]: " vhost_http_port
    read -p "HTTPS 代理端口 [443, 留空不启用]: " vhost_https_port
    
    # 生成配置
    cat > "$FRPS_CONF" << EOF
# FRPS 服务端配置
# VPS-play 自动生成

bindPort = $bind_port

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = $dashboard_port
webServer.user = "$dashboard_user"
webServer.password = "$dashboard_pwd"

# 认证配置
auth.method = "token"
auth.token = "$auth_token"
EOF

    # 添加 HTTP/HTTPS 端口
    [ -n "$vhost_http_port" ] && echo "vhostHTTPPort = $vhost_http_port" >> "$FRPS_CONF"
    [ -n "$vhost_https_port" ] && echo "vhostHTTPSPort = $vhost_https_port" >> "$FRPS_CONF"
    
    echo -e ""
    echo -e "${Info} 配置已保存: $FRPS_CONF"
    echo -e ""
    echo -e "${Green}==================== FRPS 配置信息 ====================${Reset}"
    echo -e " 服务端口:     ${Cyan}${bind_port}${Reset}"
    echo -e " Dashboard:    ${Cyan}http://${PUBLIC_IP:-YOUR_IP}:${dashboard_port}${Reset}"
    echo -e " 用户名:       ${Cyan}${dashboard_user}${Reset}"
    echo -e " 密码:         ${Cyan}${dashboard_pwd}${Reset}"
    echo -e " Token:        ${Cyan}${auth_token}${Reset}"
    echo -e "${Green}========================================================${Reset}"
    echo -e ""
    echo -e "${Tip} 客户端连接配置:"
    echo -e "  serverAddr = \"${PUBLIC_IP:-YOUR_IP}\""
    echo -e "  serverPort = $bind_port"
    echo -e "  auth.token = \"$auth_token\""
}

show_config() {
    if [ -f "$FRPS_CONF" ]; then
        echo -e "${Info} 当前配置:"
        echo -e "${Cyan}========================================${Reset}"
        cat "$FRPS_CONF"
        echo -e "${Cyan}========================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

show_client_config() {
    if [ -f "$FRPS_CONF" ]; then
        local bind_port=$(grep "^bindPort" "$FRPS_CONF" | cut -d'=' -f2 | tr -d ' ')
        local auth_token=$(grep "^auth.token" "$FRPS_CONF" | cut -d'"' -f2)
        
        echo -e ""
        echo -e "${Green}==================== 客户端配置示例 ====================${Reset}"
        echo -e ""
        echo -e "# frpc.toml 配置示例"
        echo -e "serverAddr = \"${PUBLIC_IP:-YOUR_IP}\""
        echo -e "serverPort = ${bind_port:-7000}"
        echo -e "auth.token = \"${auth_token}\""
        echo -e ""
        echo -e "# TCP 隧道示例"
        echo -e "[[proxies]]"
        echo -e "name = \"ssh\""
        echo -e "type = \"tcp\""
        echo -e "localIP = \"127.0.0.1\""
        echo -e "localPort = 22"
        echo -e "remotePort = 6000"
        echo -e ""
        echo -e "${Green}========================================================${Reset}"
    else
        echo -e "${Warning} 请先创建配置"
    fi
}

# ==================== 服务管理 ====================
start_frps() {
    if [ ! -f "$FRPS_BIN" ]; then
        echo -e "${Error} FRPS 未安装"
        return 1
    fi
    
    if [ ! -f "$FRPS_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 FRPS..."
    start_process "frps" "$FRPS_BIN -c $FRPS_CONF" "$FRPS_DIR"
    
    sleep 2
    if status_process "frps" &>/dev/null; then
        echo -e "${Info} FRPS 启动成功"
        
        local dashboard_port=$(grep "webServer.port" "$FRPS_CONF" | cut -d'=' -f2 | tr -d ' ')
        echo -e "${Info} Dashboard: ${Cyan}http://${PUBLIC_IP:-YOUR_IP}:${dashboard_port:-7500}${Reset}"
    else
        echo -e "${Error} 启动失败"
    fi
}

stop_frps() {
    echo -e "${Info} 停止 FRPS..."
    stop_process "frps"
}

restart_frps() {
    stop_frps
    sleep 1
    start_frps
}

status_frps() {
    status_process "frps"
}

# ==================== 卸载 ====================
uninstall_frps() {
    echo -e "${Warning} 确定要卸载 FRPS? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_frps
    rm -rf "$FRPS_DIR"
    echo -e "${Info} 已卸载"
}

# ==================== 主菜单 ====================
show_frps_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦═╗╔═╗╔═╗
    ╠╣ ╠╦╝╠═╝╚═╗
    ╚  ╩╚═╩  ╚═╝
    内网穿透服务端
EOF
        echo -e "${Reset}"
        
        if [ -f "$FRPS_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "frps" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== FRPS 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 FRPS"
        echo -e " ${Green}2.${Reset}  卸载 FRPS"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  创建/修改配置"
        echo -e " ${Green}4.${Reset}  查看配置"
        echo -e " ${Green}5.${Reset}  生成客户端配置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}6.${Reset}  启动"
        echo -e " ${Green}7.${Reset}  停止"
        echo -e " ${Green}8.${Reset}  重启"
        echo -e " ${Green}9.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-9]: " choice
        
        case "$choice" in
            1) download_frps ;;
            2) uninstall_frps ;;
            3) create_config ;;
            4) show_config ;;
            5) show_client_config ;;
            6) start_frps ;;
            7) stop_frps ;;
            8) restart_frps ;;
            9) status_frps ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_frps_menu
fi
