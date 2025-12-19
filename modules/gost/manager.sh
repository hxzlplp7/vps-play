#!/bin/bash
# GOST 模块 - VPS-play
# 整合 gost-serv00.sh，适配多环境

# 获取脚本目录
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/gost"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

# 加载 VPS-play 工具库
[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
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

# ==================== 环境适配 ====================
# 根据环境设置 GOST 配置
setup_gost_environment() {
    # 检测环境
    if [ -z "$ENV_TYPE" ]; then
        detect_environment 2>/dev/null || ENV_TYPE="vps"
    fi
    
    # 根据环境设置工作目录
    export GOST_DIR="$HOME/.vps-play/gost"
    export GOST_BIN="$GOST_DIR/gost"
    export GOST_CONF="$GOST_DIR/config.yaml"
    
    mkdir -p "$GOST_DIR"
    
    echo -e "${Info} GOST 环境: ${Cyan}${ENV_TYPE}${Reset}"
    
    # 设置端口管理方式
    detect_port_method 2>/dev/null || PORT_METHOD="direct"
}

# ==================== 端口集成 ====================
# 使用 VPS-play 的端口管理
gost_add_port() {
    local port=$1
    local proto=${2:-tcp}
    
    echo -e "${Info} 添加端口 $port ($proto)..."
    
    # 调用统一的端口管理接口
    add_port "$port" "$proto"
    
    if [ $? -eq 0 ]; then
        # 保存到 GOST 配置
        echo "$port:$proto" >> "$GOST_DIR/ports.list"
        return 0
    else
        return 1
    fi
}

# ==================== 进程集成 ====================
# 使用 VPS-play 的进程管理启动 GOST
gost_start_service() {
    echo -e "${Info} 启动 GOST 服务..."
    
    if [ ! -f "$GOST_BIN" ]; then
        echo -e "${Error} GOST 未安装"
        return 1
    fi
    
    # 使用统一的进程管理
    start_process "gost" "$GOST_BIN -C $GOST_CONF" "$GOST_DIR"
}

# 停止 GOST 服务
gost_stop_service() {
    echo -e "${Info} 停止 GOST 服务..."
    stop_process "gost"
}

# 重启 GOST 服务
gost_restart_service() {
    echo -e "${Info} 重启 GOST 服务..."
    restart_process "gost"
}

# 查看 GOST 状态
gost_status() {
    status_process "gost"
}

# ==================== 主菜单 ====================
show_gost_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╔═╗╔═╗╔╦╗  ╦  ╦╔═╗
    ║ ╦║ ║╚═╗ ║   ╚╗╔╝╚═╗
    ╚═╝╚═╝╚═╝ ╩    ╚╝  ╩ 
    流量中转工具
EOF
        echo -e "${Reset}"
        echo -e "  环境: ${Yellow}${ENV_TYPE}${Reset} | 端口管理: ${Cyan}${PORT_METHOD}${Reset}"
        echo -e ""
        echo -e "${Green}==================== GOST 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 GOST"
        echo -e " ${Green}2.${Reset}  卸载 GOST"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  启动服务"
        echo -e " ${Green}4.${Reset}  停止服务"
        echo -e " ${Green}5.${Reset}  重启服务"
        echo -e " ${Green}6.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  添加中转"
        echo -e " ${Green}8.${Reset}  查看配置"
        echo -e " ${Green}9.${Reset}  删除配置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}10.${Reset} 查看日志"
        echo -e " ${Green}11.${Reset} 端口管理"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-11]: " choice
        
        case "$choice" in
            1)
                # 调用原始的安装脚本
                bash "$MODULE_DIR/gost.sh" << INSTALL_EOF
1
0
INSTALL_EOF
                ;;
            2)
                bash "$MODULE_DIR/gost.sh" << UNINSTALL_EOF
2
0
UNINSTALL_EOF
                ;;
            3)
                gost_start_service
                ;;
            4)
                gost_stop_service
                ;;
            5)
                gost_restart_service
                ;;
            6)
                gost_status
                ;;
            7)
                # 调用原始脚本的添加功能
                bash "$MODULE_DIR/gost.sh" << ADD_EOF
7
0
ADD_EOF
                ;;
            8)
                bash "$MODULE_DIR/gost.sh" << VIEW_EOF
8
0
VIEW_EOF
                ;;
            9)
                bash "$MODULE_DIR/gost.sh" << DEL_EOF
9
0
DEL_EOF
                ;;
            10)
                bash "$MODULE_DIR/gost.sh" << LOG_EOF
6
0
LOG_EOF
                ;;
            11)
                # 调用 VPS-play 的端口管理
                source "$VPSPLAY_DIR/start.sh"
                port_manage_menu
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${Error} 无效选择"
                ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
main() {
    setup_gost_environment
    show_gost_menu
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
