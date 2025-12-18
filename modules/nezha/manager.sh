#!/bin/bash
# 哪吒监控模块 - VPS-play
# 哪吒监控 Agent 安装和管理

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

source "$VPSPLAY_DIR/utils/env_detect.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/process_manager.sh" 2>/dev/null

# ==================== 配置 ====================
NEZHA_DIR="$HOME/.vps-play/nezha"
NEZHA_BIN="$NEZHA_DIR/nezha-agent"
NEZHA_CONF="$NEZHA_DIR/config.yml"
NEZHA_LOG="$NEZHA_DIR/nezha.log"

mkdir -p "$NEZHA_DIR"

# ==================== 下载安装 ====================
download_nezha_agent() {
    echo -e "${Info} 正在下载哪吒监控 Agent..."
    
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
        386) arch_type="386" ;;
    esac
    
    local download_url="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_${os_type}_${arch_type}.zip"
    
    cd "$NEZHA_DIR"
    
    # 下载
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o nezha-agent.zip
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O nezha-agent.zip
    fi
    
    # 解压
    if command -v unzip &>/dev/null; then
        unzip -o nezha-agent.zip
    else
        echo -e "${Error} 需要 unzip 工具"
        return 1
    fi
    
    rm -f nezha-agent.zip
    chmod +x nezha-agent
    
    echo -e "${Info} 哪吒 Agent 下载完成"
}

# ==================== 配置管理 ====================
configure_agent() {
    echo -e ""
    echo -e "${Info} 配置哪吒监控 Agent"
    echo -e "${Tip} 请在哪吒面板后台获取以下信息"
    echo -e ""
    
    read -p "面板地址 (如 data.example.com): " server_addr
    read -p "面板端口 [5555]: " server_port
    server_port=${server_port:-5555}
    read -p "Agent 密钥: " agent_secret
    
    if [ -z "$server_addr" ] || [ -z "$agent_secret" ]; then
        echo -e "${Error} 地址和密钥不能为空"
        return 1
    fi
    
    # 保存配置
    cat > "$NEZHA_CONF" << EOF
server: $server_addr
port: $server_port
secret: $agent_secret
tls: false
debug: false
EOF
    
    echo -e "${Info} 配置已保存"
}

show_config() {
    if [ -f "$NEZHA_CONF" ]; then
        echo -e "${Info} 当前配置:"
        echo -e "${Cyan}========================================${Reset}"
        cat "$NEZHA_CONF"
        echo -e "${Cyan}========================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

# ==================== 服务管理 ====================
start_nezha() {
    if [ ! -f "$NEZHA_BIN" ]; then
        echo -e "${Error} 哪吒 Agent 未安装"
        return 1
    fi
    
    if [ ! -f "$NEZHA_CONF" ]; then
        echo -e "${Error} 配置文件不存在，请先配置"
        return 1
    fi
    
    # 读取配置
    local server=$(grep "^server:" "$NEZHA_CONF" | cut -d' ' -f2)
    local port=$(grep "^port:" "$NEZHA_CONF" | cut -d' ' -f2)
    local secret=$(grep "^secret:" "$NEZHA_CONF" | cut -d' ' -f2)
    local tls=$(grep "^tls:" "$NEZHA_CONF" | cut -d' ' -f2)
    
    local tls_flag=""
    [ "$tls" = "true" ] && tls_flag="--tls"
    
    echo -e "${Info} 启动哪吒 Agent..."
    start_process "nezha" "$NEZHA_BIN -s ${server}:${port} -p ${secret} $tls_flag" "$NEZHA_DIR"
    
    sleep 2
    if status_process "nezha" &>/dev/null; then
        echo -e "${Info} 哪吒 Agent 启动成功"
    else
        echo -e "${Error} 启动失败"
    fi
}

stop_nezha() {
    echo -e "${Info} 停止哪吒 Agent..."
    stop_process "nezha"
}

restart_nezha() {
    stop_nezha
    sleep 1
    start_nezha
}

status_nezha() {
    status_process "nezha"
}

# ==================== 卸载 ====================
uninstall_nezha() {
    echo -e "${Warning} 确定要卸载哪吒 Agent? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_nezha
    rm -rf "$NEZHA_DIR"
    echo -e "${Info} 已卸载"
}

# ==================== 一键安装 ====================
quick_install() {
    echo -e "${Info} 开始一键安装哪吒 Agent..."
    
    # 下载
    download_nezha_agent
    
    # 配置
    configure_agent
    
    # 启动
    start_nezha
    
    echo -e ""
    echo -e "${Info} 安装完成！请在哪吒面板查看是否上线"
}

# ==================== 主菜单 ====================
show_nezha_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔╗╔╔═╗╔═╗╦ ╦╔═╗
    ║║║║╣ ╔═╝╠═╣╠═╣
    ╝╚╝╚═╝╚═╝╩ ╩╩ ╩
    哪吒监控 Agent
EOF
        echo -e "${Reset}"
        
        if [ -f "$NEZHA_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "nezha" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== 哪吒监控管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键安装"
        echo -e " ${Green}2.${Reset}  下载 Agent"
        echo -e " ${Green}3.${Reset}  卸载"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}4.${Reset}  配置 Agent"
        echo -e " ${Green}5.${Reset}  查看配置"
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
            1) quick_install ;;
            2) download_nezha_agent ;;
            3) uninstall_nezha ;;
            4) configure_agent ;;
            5) show_config ;;
            6) start_nezha ;;
            7) stop_nezha ;;
            8) restart_nezha ;;
            9) status_nezha ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_nezha_menu
fi
