#!/bin/bash
# VPS-play 主脚本
# 支持: 普通VPS、NAT VPS、FreeBSD、Serv00/Hostuno
# 功能: 节点管理、保活、域名、SSL、监控等

version="1.0.0"

# ==================== 初始化 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$HOME/.vps-play"

# 加载工具库
source "$SCRIPT_DIR/utils/env_detect.sh"
source "$SCRIPT_DIR/utils/port_manager.sh"
source "$SCRIPT_DIR/utils/process_manager.sh"
source "$SCRIPT_DIR/utils/network.sh"

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
    mkdir -p "$WORK_DIR"/{modules,config,logs,keepalive}
    
    # 检测或加载环境信息
    if ! load_env_info "$WORK_DIR/env.conf"; then
        detect_environment
        save_env_info "$WORK_DIR/env.conf"
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
    echo -e " ${Green}4.${Reset}  FRPC 内网穿透"
    echo -e " ${Green}5.${Reset}  Cloudflared 隧道"
    echo -e " ${Green}6.${Reset}  哪吒监控"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Yellow}系统工具${Reset}"
    echo -e " ${Green}11.${Reset} 端口管理"
    echo -e " ${Green}12.${Reset} 进程管理"
    echo -e " ${Green}13.${Reset} 网络工具"
    echo -e " ${Green}14.${Reset} 环境检测"
    echo -e " ${Green}15.${Reset} 保活设置"
    echo -e " ${Green}16.${Reset} 更新脚本"
    echo -e "${Green}---------------------------------------------------${Reset}"
    echo -e " ${Green}0.${Reset}  退出"
    echo -e "${Green}=================================================${Reset}"
}

# ==================== 主循环 ====================
    while true; do
        show_main_menu
        
        read -p " 请选择 [0-16]: " choice
        
        case "$choice" in
            1)
                # sing-box 模块
                if [ -f "$SCRIPT_DIR/modules/singbox/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/singbox/manager.sh"
                else
                    echo -e "${Error} sing-box 模块未找到"
                fi
                ;;
            2)
                # GOST 中转模块
                if [ -f "$SCRIPT_DIR/modules/gost/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/gost/manager.sh"
                else
                    echo -e "${Error} GOST 模块未找到"
                fi
                ;;
            3)
                # X-UI 模块
                if [ -f "$SCRIPT_DIR/modules/xui/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/xui/manager.sh"
                else
                    echo -e "${Error} X-UI 模块未找到"
                fi
                ;;
            4)
                # FRPC 模块
                if [ -f "$SCRIPT_DIR/modules/frpc/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/frpc/manager.sh"
                else
                    echo -e "${Error} FRPC 模块未找到"
                fi
                ;;
            5)
                # Cloudflared 模块
                if [ -f "$SCRIPT_DIR/modules/cloudflared/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/cloudflared/manager.sh"
                else
                    echo -e "${Error} Cloudflared 模块未找到"
                fi
                ;;
            6)
                # 哪吒监控模块
                if [ -f "$SCRIPT_DIR/modules/nezha/manager.sh" ]; then
                    bash "$SCRIPT_DIR/modules/nezha/manager.sh"
                else
                    echo -e "${Error} 哪吒监控模块未找到"
                fi
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
                if [ -f "$SCRIPT_DIR/start.sh.new" ]; then
                    mv "$SCRIPT_DIR/start.sh.new" "$SCRIPT_DIR/start.sh"
                    chmod +x "$SCRIPT_DIR/start.sh"
                    echo -e "${Info} 更新完成，请重新运行脚本"
                    exit 0
                fi
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
