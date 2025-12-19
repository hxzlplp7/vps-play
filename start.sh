#!/bin/bash
# VPS-play 主脚本
# 支持: 普通VPS、NAT VPS、FreeBSD、Serv00/Hostuno
# 功能: 节点管理、保活、域名、SSL、监控等

version="1.0.0"

# ==================== 初始化 ====================
# 获取脚本目录 - 解析所有符号链接，确保得到真实路径
SCRIPT_DIR=""

# 方法1：BASH_SOURCE（优先） → 解析真实路径
if [ -n "${BASH_SOURCE[0]}" ]; then
    if command -v readlink >/dev/null 2>&1; then
        _src=$(readlink -f "${BASH_SOURCE[0]}")
    else
        _src="${BASH_SOURCE[0]}"
    fi
    _dir=$(cd "$(dirname "$_src")" && pwd)
    [ -d "$_dir/modules" ] && SCRIPT_DIR="$_dir"
fi

# 方法2：$0（当脚本直接执行时） → 解析真实路径
if [ -z "$SCRIPT_DIR" ] && [ -n "$0" ] && [ "$0" != "bash" ]; then
    if command -v readlink >/dev/null 2>&1; then
        _src=$(readlink -f "$0")
    else
        _src="$0"
    fi
    _dir=$(cd "$(dirname "$_src")" && pwd)
    [ -d "$_dir/modules" ] && SCRIPT_DIR="$_dir"
fi

# 方法3：常见安装路径（兼容手动拷贝或软链接到其他目录的情况）
if [ -z "$SCRIPT_DIR" ]; then
    for _path in "$HOME/vps-play" "/root/vps-play" "/usr/local/vps-play" "$HOME/.vps-play"; do
        [ -d "$_path/modules" ] && SCRIPT_DIR="$_path" && break
    done
fi

# 方法4：最终回退（不影响功能，只是给出友好提示）
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="$HOME/vps-play"

WORK_DIR="$HOME/.vps-play"

# 加载工具库（静默失败）
[ -f "$SCRIPT_DIR/utils/env_detect.sh" ] && source "$SCRIPT_DIR/utils/env_detect.sh"
[ -f "$SCRIPT_DIR/utils/port_manager.sh" ] && source "$SCRIPT_DIR/utils/port_manager.sh"
[ -f "$SCRIPT_DIR/utils/process_manager.sh" ] && source "$SCRIPT_DIR/utils/process_manager.sh"
[ -f "$SCRIPT_DIR/utils/network.sh" ] && source "$SCRIPT_DIR/utils/network.sh"
[ -f "$SCRIPT_DIR/utils/system_clean.sh" ] && source "$SCRIPT_DIR/utils/system_clean.sh"

# ==================== 颜色定义 ====================
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Blue="\033[34m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"
Tip="${Cyan}[提示]${Reset}"

# ==================== 初始化环境 ====================
init_environment() {
    mkdir -p "$WORK_DIR"/{modules,config,logs,keepalive,processes}
    
    # 检测或加载环境信息
    if [ -f "$WORK_DIR/env.conf" ]; then
        source "$WORK_DIR/env.conf"
    fi
    
    # 如果环境变量为空，重新检测
    if [ -z "$ENV_TYPE" ] || [ -z "$OS_DISTRO" ]; then
        # 静默检测
        detect_os_silent
        detect_arch_silent
        detect_virt_silent
        detect_permissions_silent
        detect_services_silent
        detect_network_silent
        determine_env_type_silent
        
        # 保存配置
        save_env_info "$WORK_DIR/env.conf" 2>/dev/null
    fi
}

# 静默版本的检测函数
detect_os_silent() {
    local os=$(uname -s)
    case "$os" in
        Linux)
            OS_TYPE="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
            elif [ -f /etc/redhat-release ]; then
                OS_DISTRO="centos"
            elif [ -f /etc/debian_version ]; then
                OS_DISTRO="debian"
            else
                OS_DISTRO="linux"
            fi
            ;;
        FreeBSD)
            OS_TYPE="freebsd"
            OS_DISTRO="freebsd"
            ;;
        *)
            OS_TYPE="unknown"
            OS_DISTRO="unknown"
            ;;
    esac
}

detect_arch_silent() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="386" ;;
        *) ARCH="unknown" ;;
    esac
}

detect_permissions_silent() {
    if [ "$(id -u)" = "0" ]; then
        HAS_ROOT=true
    else
        HAS_ROOT=false
    fi
}

detect_services_silent() {
    if command -v systemctl &>/dev/null && systemctl &>/dev/null 2>&1; then
        HAS_SYSTEMD=true
    else
        HAS_SYSTEMD=false
    fi
    
    if command -v devil &>/dev/null; then
        HAS_DEVIL=true
    else
        HAS_DEVIL=false
    fi
}

detect_network_silent() {
    PUBLIC_IP=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo "unknown")
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
    
    if [ "$PUBLIC_IP" != "$LOCAL_IP" ] && [ "$PUBLIC_IP" != "unknown" ] && [ "$LOCAL_IP" != "unknown" ]; then
        IS_NAT=true
    else
        IS_NAT=false
    fi
}

determine_env_type_silent() {
    if [ "$HAS_DEVIL" = true ]; then
        ENV_TYPE="serv00"
    elif [ "$OS_TYPE" = "freebsd" ]; then
        ENV_TYPE="freebsd"
    elif [ "$IS_NAT" = true ]; then
        ENV_TYPE="natvps"
    elif [ "$HAS_ROOT" = true ]; then
        ENV_TYPE="vps"
    else
        ENV_TYPE="limited"
    fi
}

detect_virt_silent() {
    IS_CONTAINER=false
    VIRT_TYPE="none"
    
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        VIRT_TYPE="docker"
        IS_CONTAINER=true
    elif [ -f /run/.containerenv ]; then
        VIRT_TYPE="podman"
        IS_CONTAINER=true
    elif command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    fi
}

# ==================== 显示 Logo ====================
show_logo() {
    clear
    echo -e "${Cyan}"
    cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    通用 VPS 管理工具
EOF
    echo -e "${Reset}"
    echo -e "  版本: ${Green}v${version}${Reset}"
    echo -e "  环境: ${Yellow}${ENV_TYPE}${Reset} | ${Cyan}${OS_DISTRO}${Reset} | ${Blue}${ARCH}${Reset}"
    echo -e ""
}

# ==================== 模块管理 ====================
list_modules() {
    echo -e "${Green}==================== 可用模块 ====================${Reset}"
    echo -e " ${Green}1.${Reset}  sing-box    - 通用代理节点"
    echo -e " ${Green}2.${Reset}  GOST        - 流量中转工具"
    echo -e " ${Green}3.${Reset}  X-UI        - 可视化面板"
    echo -e " ${Green}4.${Reset}  FRPC        - 内网穿透客户端"
    echo -e " ${Green}5.${Reset}  Cloudflared - Cloudflare隧道"
    echo -e " ${Green}6.${Reset}  哪吒监控    - 服务器监控"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 系统工具菜单 ====================
show_tools_menu() {
    echo -e ""
    echo -e "${Green}==================== 系统工具 ====================${Reset}"
    echo -e " ${Green}1.${Reset}  端口管理"
    echo -e " ${Green}2.${Reset}  环境检测"
    echo -e " ${Green}3.${Reset}  保活设置"
    echo -e " ${Green}4.${Reset}  更新脚本"
    echo -e " ${Green}0.${Reset}  返回"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 端口管理菜单 ====================
port_manage_menu() {
    while true; do
        echo -e ""
        echo -e "${Green}==================== 端口管理 ====================${Reset}"
        echo -e " 当前方式: ${Cyan}${PORT_METHOD}${Reset}"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}1.${Reset}  添加端口"
        echo -e " ${Green}2.${Reset}  删除端口"
        echo -e " ${Green}3.${Reset}  列出所有端口"
        echo -e " ${Green}4.${Reset}  检查端口可用性"
        echo -e " ${Green}5.${Reset}  获取随机端口"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-5]: " choice
        
        case "$choice" in
            1)
                echo -e ""
                read -p "请输入端口号: " port
                read -p "协议类型 [tcp/udp/both] (默认tcp): " proto
                proto=${proto:-tcp}
                
                if [ "$PORT_METHOD" = "socat" ]; then
                    read -p "目标主机: " target_host
                    read -p "目标端口: " target_port
                    add_port "$port" "$proto" "$target_host" "$target_port"
                elif [ "$PORT_METHOD" = "iptables" ]; then
                    read -p "目标端口: " target_port
                    add_port "$port" "$proto" "" "$target_port"
                else
                    add_port "$port" "$proto"
                fi
                ;;
            2)
                echo -e ""
                read -p "请输入要删除的端口: " port
                read -p "协议类型 [tcp/udp/both] (默认tcp): " proto
                proto=${proto:-tcp}
                del_port "$port" "$proto"
                ;;
            3)
                echo -e ""
                list_ports
                ;;
            4)
                echo -e ""
                read -p "请输入要检查的端口: " port
                if check_port_available "$port"; then
                    echo -e "${Info} 端口 $port 可用"
                else
                    echo -e "${Warning} 端口 $port 已被占用"
                fi
                ;;
            5)
                port=$(get_random_port 10000 65535)
                echo -e "${Info} 随机可用端口: ${Green}$port${Reset}"
                ;;
            0)
                break
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主菜单 ====================
show_main_menu() {
    show_logo
    
    echo -e "${Green}==================== 主菜单 ====================${Reset}"
    echo -e " ${Green}模块管理${Reset}"
    echo -e " ${Green}1.${Reset}  sing-box 节点"
    echo -e " ${Green}2.${Reset}  GOST 中转"
    echo -e " ${Green}3.${Reset}  X-UI 面板"
    echo -e " ${Green}4.${Reset}  FRPC 客户端"
    echo -e " ${Green}5.${Reset}  FRPS 服务端"
    echo -e " ${Green}6.${Reset}  Cloudflared 隧道"
    echo -e " ${Green}7.${Reset}  哪吒监控"
    echo -e " ${Green}8.${Reset}  WARP 代理"
    echo -e " ${Green}9.${Reset}  Docker 管理"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Yellow}系统工具${Reset}"
    echo -e " ${Green}11.${Reset} 端口管理"
    echo -e " ${Green}12.${Reset} 进程管理"
    echo -e " ${Green}13.${Reset} 网络工具"
    echo -e " ${Green}14.${Reset} 环境检测"
    echo -e " ${Green}15.${Reset} 保活设置"
    echo -e " ${Green}16.${Reset} 更新脚本"
    echo -e " ${Green}17.${Reset} 系统清理"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Green}0.${Reset}  退出"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 运行模块 ====================
run_module() {
    local module_name=$1
    local module_path=$2
    
    # 尝试多个可能的路径
    local paths=(
        "$SCRIPT_DIR/$module_path"
        "$HOME/vps-play/$module_path"
        "/root/vps-play/$module_path"
    )
    
    for path in "${paths[@]}"; do
        if [ -f "$path" ]; then
            bash "$path"
            return 0
        fi
    done
    
    echo -e "${Error} $module_name 模块未找到"
    echo -e "${Tip} 请检查安装目录: $SCRIPT_DIR"
    echo -e "${Tip} 尝试重新安装: curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash"
    return 1
}

# ==================== 主循环 ====================
    while true; do
        show_main_menu
        
        read -p " 请选择 [0-17]: " choice
        
        case "$choice" in
            1)
                run_module "sing-box" "modules/singbox/manager.sh"
            # ... (其他 case) 保持不变，我只替换 case 开始和添加最后的 case

                ;;
            2)
                run_module "GOST" "modules/gost/manager.sh"
                ;;
            3)
                run_module "X-UI" "modules/xui/manager.sh"
                ;;
            4)
                run_module "FRPC" "modules/frpc/manager.sh"
                ;;
            5)
                run_module "FRPS" "modules/frps/manager.sh"
                ;;
            6)
                run_module "Cloudflared" "modules/cloudflared/manager.sh"
                ;;
            7)
                run_module "哪吒监控" "modules/nezha/manager.sh"
                ;;
            8)
                run_module "WARP" "modules/warp/manager.sh"
                ;;
            9)
                run_module "Docker" "modules/docker/manager.sh"
                ;;
            11)
                port_manage_menu
                ;;
            12)
                # 进程管理
                echo -e "${Info} 进程管理工具:"
                list_processes
                ;;
            13)
                # 网络工具
                network_info
                ;;
            14)
                detect_environment
                show_env_info
                ;;
            15)
                # 保活系统
                if [ -f "$SCRIPT_DIR/keepalive/manager.sh" ]; then
                    bash "$SCRIPT_DIR/keepalive/manager.sh"
                else
                    echo -e "${Error} 保活模块未找到"
                fi
                ;;
            16)
                echo -e "${Info} 更新脚本..."
                curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/start.sh -o "$SCRIPT_DIR/start.sh.new"
                if [ -s "$SCRIPT_DIR/start.sh.new" ]; then
                    mv "$SCRIPT_DIR/start.sh.new" "$SCRIPT_DIR/start.sh"
                    chmod +x "$SCRIPT_DIR/start.sh"
                    echo -e "${Info} 更新完成，请重新运行脚本"
                    exit 0
                else
                    echo -e "${Error} 更新失败"
                fi
                ;;
            17)
                clean_system
                ;;
            0)
                echo -e "${Info} 感谢使用 VPS-play!"
                exit 0
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 入口 ====================
main() {
    init_environment
    main_loop
}

main
