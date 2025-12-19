#!/bin/bash
# Cloudflared 模块 - VPS-play
# Cloudflare Tunnel 管理

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/cloudflared"
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
CFD_DIR="$HOME/.vps-play/cloudflared"
CFD_BIN="$CFD_DIR/cloudflared"
CFD_CONF="$CFD_DIR/config.yml"
CFD_LOG="$CFD_DIR/cloudflared.log"
CFD_CRED_DIR="$CFD_DIR/credentials"

mkdir -p "$CFD_DIR" "$CFD_CRED_DIR"

# ==================== 下载安装 ====================
download_cloudflared() {
    echo -e "${Info} 正在下载 Cloudflared..."
    
    local download_url=""
    
    case "$OS_TYPE" in
        linux)
            case "$ARCH" in
                amd64) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
                arm64) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
                armv7) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm" ;;
            esac
            ;;
        freebsd)
            download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-freebsd-amd64"
            ;;
    esac
    
    if [ -z "$download_url" ]; then
        echo -e "${Error} 不支持的系统/架构"
        return 1
    fi
    
    cd "$CFD_DIR"
    
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o cloudflared
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O cloudflared
    fi
    
    chmod +x cloudflared
    
    echo -e "${Info} Cloudflared 下载完成"
    echo -e "${Info} 版本: $($CFD_BIN version 2>/dev/null | head -1)"
}

# ==================== Tunnel 管理 ====================
# 登录 Cloudflare
cf_login() {
    echo -e "${Info} 登录 Cloudflare..."
    echo -e "${Tip} 将在浏览器中打开登录页面，请完成授权"
    
    $CFD_BIN tunnel login
    
    # 移动凭证到指定目录
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        mv "$HOME/.cloudflared/cert.pem" "$CFD_CRED_DIR/"
        echo -e "${Info} 登录成功，凭证已保存"
    fi
}

# 创建隧道
create_tunnel() {
    read -p "隧道名称: " tunnel_name
    
    if [ -z "$tunnel_name" ]; then
        echo -e "${Error} 名称不能为空"
        return 1
    fi
    
    echo -e "${Info} 创建隧道: $tunnel_name"
    
    $CFD_BIN tunnel create "$tunnel_name"
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} 隧道创建成功"
        
        # 移动凭证
        local cred_file=$(ls "$HOME/.cloudflared/"*.json 2>/dev/null | head -1)
        if [ -f "$cred_file" ]; then
            mv "$cred_file" "$CFD_CRED_DIR/"
            echo -e "${Info} 隧道凭证已保存"
        fi
    fi
}

# 列出隧道
list_tunnels() {
    echo -e "${Info} 隧道列表:"
    $CFD_BIN tunnel list
}

# 删除隧道
delete_tunnel() {
    list_tunnels
    echo -e ""
    read -p "输入要删除的隧道名称: " tunnel_name
    
    if [ -n "$tunnel_name" ]; then
        $CFD_BIN tunnel delete "$tunnel_name"
    fi
}

# ==================== 配置管理 ====================
create_config() {
    echo -e ""
    read -p "隧道 UUID (从 tunnel list 获取): " tunnel_uuid
    
    if [ -z "$tunnel_uuid" ]; then
        echo -e "${Error} UUID 不能为空"
        return 1
    fi
    
    # 查找凭证文件
    local cred_file=$(ls "$CFD_CRED_DIR"/*.json 2>/dev/null | head -1)
    if [ -z "$cred_file" ]; then
        cred_file="$CFD_CRED_DIR/${tunnel_uuid}.json"
    fi
    
    cat > "$CFD_CONF" << EOF
tunnel: $tunnel_uuid
credentials-file: $cred_file

ingress:
  # 示例: 将域名指向本地服务
  # - hostname: example.com
  #   service: http://localhost:8080
  
  # 默认: 返回 404
  - service: http_status:404
EOF
    
    echo -e "${Info} 配置文件已创建: $CFD_CONF"
    echo -e "${Tip} 请编辑配置文件添加路由规则"
}

add_route() {
    if [ ! -f "$CFD_CONF" ]; then
        echo -e "${Error} 请先创建配置文件"
        return 1
    fi
    
    echo -e ""
    read -p "域名 (如 app.example.com): " hostname
    read -p "本地服务地址 (如 http://localhost:8080): " service
    
    if [ -z "$hostname" ] || [ -z "$service" ]; then
        echo -e "${Error} 域名和服务地址不能为空"
        return 1
    fi
    
    # 在 ingress 部分添加路由（在最后的 catch-all 之前）
    sed -i "/- service: http_status:404/i\\
  - hostname: $hostname\\
    service: $service" "$CFD_CONF"
    
    echo -e "${Info} 路由已添加: $hostname -> $service"
    echo -e "${Tip} 请在 Cloudflare DNS 中添加 CNAME 记录指向隧道"
}

show_config() {
    if [ -f "$CFD_CONF" ]; then
        echo -e "${Info} 当前配置:"
        echo -e "${Cyan}========================================${Reset}"
        cat "$CFD_CONF"
        echo -e "${Cyan}========================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

# ==================== 服务管理 ====================
start_cloudflared() {
    if [ ! -f "$CFD_BIN" ]; then
        echo -e "${Error} Cloudflared 未安装"
        return 1
    fi
    
    if [ ! -f "$CFD_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 Cloudflared..."
    start_process "cloudflared" "$CFD_BIN tunnel --config $CFD_CONF run" "$CFD_DIR"
}

stop_cloudflared() {
    echo -e "${Info} 停止 Cloudflared..."
    stop_process "cloudflared"
}

restart_cloudflared() {
    stop_cloudflared
    sleep 1
    start_cloudflared
}

# ==================== Quick Tunnel ====================
quick_tunnel() {
    echo -e "${Info} 启动 Quick Tunnel (临时隧道)"
    echo -e "${Tip} 这将创建一个临时的公网地址，重启后失效"
    echo -e ""
    
    read -p "本地服务地址 (如 http://localhost:8080): " local_service
    
    if [ -z "$local_service" ]; then
        echo -e "${Error} 地址不能为空"
        return 1
    fi
    
    echo -e "${Info} 启动中... 按 Ctrl+C 停止"
    $CFD_BIN tunnel --url "$local_service"
}

# ==================== 主菜单 ====================
show_cfd_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦  ╔═╗╦ ╦╔╦╗╔═╗╦  ╔═╗╦═╗╔═╗╔╦╗
    ║  ║  ║ ║║ ║ ║║╠╣ ║  ╠═╣╠╦╝║╣  ║║
    ╚═╝╩═╝╚═╝╚═╝═╩╝╚  ╩═╝╩ ╩╩╚═╚═╝═╩╝
    Cloudflare Tunnel
EOF
        echo -e "${Reset}"
        
        if [ -f "$CFD_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "cloudflared" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== Cloudflared 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 Cloudflared"
        echo -e " ${Green}2.${Reset}  卸载 Cloudflared"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  登录 Cloudflare"
        echo -e " ${Green}4.${Reset}  创建隧道"
        echo -e " ${Green}5.${Reset}  列出隧道"
        echo -e " ${Green}6.${Reset}  删除隧道"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  创建配置"
        echo -e " ${Green}8.${Reset}  添加路由"
        echo -e " ${Green}9.${Reset}  查看配置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}10.${Reset} 启动"
        echo -e " ${Green}11.${Reset} 停止"
        echo -e " ${Green}12.${Reset} 重启"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}13.${Reset} Quick Tunnel (临时隧道)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-13]: " choice
        
        case "$choice" in
            1) download_cloudflared ;;
            2) stop_cloudflared; rm -rf "$CFD_DIR"; echo -e "${Info} 已卸载" ;;
            3) cf_login ;;
            4) create_tunnel ;;
            5) list_tunnels ;;
            6) delete_tunnel ;;
            7) create_config ;;
            8) add_route ;;
            9) show_config ;;
            10) start_cloudflared ;;
            11) stop_cloudflared ;;
            12) restart_cloudflared ;;
            13) quick_tunnel ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_cfd_menu
fi
