#!/bin/bash
# X-UI 模块 - VPS-play
# 适配多环境的 X-UI 面板安装和管理

# 获取脚本目录
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/xui"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

# 加载 VPS-play 工具库
[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

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
XUI_DIR="$HOME/.vps-play/xui"
XUI_BIN="$XUI_DIR/x-ui"
XUI_DB="$XUI_DIR/x-ui.db"
XUI_LOG="$XUI_DIR/x-ui.log"
XUI_PORT=${XUI_PORT:-54321}

# x-ui 版本
XUI_VERSION="0.3.4.4"
XUI_REPO="https://github.com/MHSanaei/3x-ui"

# ==================== 初始化 ====================
init_xui() {
    mkdir -p "$XUI_DIR"
    
    # 检测环境
    if [ -z "$ENV_TYPE" ]; then
        detect_environment 2>/dev/null || ENV_TYPE="vps"
    fi
    
    echo -e "${Info} X-UI 工作目录: $XUI_DIR"
    echo -e "${Info} 环境类型: ${Cyan}${ENV_TYPE}${Reset}"
}

# ==================== 下载安装 ====================
download_xui() {
    echo -e "${Info} 正在下载 X-UI..."
    
    # 确定下载链接
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
        386) arch_type="386" ;;
    esac
    
    local download_url="${XUI_REPO}/releases/download/v${XUI_VERSION}/x-ui-${os_type}-${arch_type}.tar.gz"
    
    echo -e "${Info} 下载地址: $download_url"
    
    cd "$XUI_DIR"
    
    # 下载
    if command -v curl &>/dev/null; then
        curl -sL "$download_url" -o x-ui.tar.gz
    elif command -v wget &>/dev/null; then
        wget -q "$download_url" -O x-ui.tar.gz
    else
        echo -e "${Error} 需要 curl 或 wget"
        return 1
    fi
    
    # 解压
    echo -e "${Info} 解压文件..."
    tar -xzf x-ui.tar.gz
    rm -f x-ui.tar.gz
    
    # 设置权限
    chmod +x x-ui bin/xray-linux-*
    
    echo -e "${Info} X-UI 下载完成"
}

# ==================== 安装 X-UI ====================
install_xui() {
    init_xui
    
    # 检查是否已安装
    if [ -f "$XUI_BIN" ]; then
        echo -e "${Warning} X-UI 已安装"
        read -p "是否重新安装? [y/N]: " reinstall
        [[ ! $reinstall =~ ^[Yy]$ ]] && return 0
    fi
    
    # 下载
    download_xui
    
    # 配置端口
    echo -e ""
    echo -e "${Info} 配置 X-UI 面板端口"
    
    # 使用 VPS-play 端口管理
    if [ "$ENV_TYPE" = "serv00" ]; then
        echo -e "${Warning} Serv00 环境需要先添加端口"
        read -p "请输入面板端口 (已通过 devil 添加): " panel_port
        XUI_PORT=${panel_port:-54321}
    else
        read -p "请输入面板端口 [默认 54321]: " panel_port
        XUI_PORT=${panel_port:-54321}
        
        # 检查端口可用性
        if ! check_port_available "$XUI_PORT"; then
            echo -e "${Warning} 端口 $XUI_PORT 已被占用"
        fi
    fi
    
    # 配置用户名密码
    echo -e ""
    read -p "管理员用户名 [默认 admin]: " admin_user
    admin_user=${admin_user:-admin}
    
    read -p "管理员密码 [默认 admin]: " admin_pass
    admin_pass=${admin_pass:-admin}
    
    # 创建配置
    cat > "$XUI_DIR/config.json" << EOF
{
    "webPort": $XUI_PORT,
    "username": "$admin_user",
    "password": "$admin_pass",
    "webBasePath": "/",
    "webCertFile": "",
    "webKeyFile": ""
}
EOF
    
    echo -e ""
    echo -e "${Info} X-UI 安装完成!"
    echo -e "${Green}========================================${Reset}"
    echo -e " 面板地址: ${Cyan}http://${PUBLIC_IP:-YOUR_IP}:${XUI_PORT}${Reset}"
    echo -e " 用户名:   ${Cyan}${admin_user}${Reset}"
    echo -e " 密码:     ${Cyan}${admin_pass}${Reset}"
    echo -e "${Green}========================================${Reset}"
    
    # 询问是否启动
    read -p "是否立即启动 X-UI? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_xui
}

# ==================== 启动 X-UI ====================
start_xui() {
    echo -e "${Info} 启动 X-UI..."
    
    if [ ! -f "$XUI_BIN" ]; then
        echo -e "${Error} X-UI 未安装"
        return 1
    fi
    
    # 使用进程管理启动
    cd "$XUI_DIR"
    start_process "x-ui" "./x-ui" "$XUI_DIR"
    
    sleep 2
    
    if status_process "x-ui" &>/dev/null; then
        echo -e "${Info} X-UI 启动成功"
        echo -e "${Info} 访问地址: ${Cyan}http://${PUBLIC_IP:-YOUR_IP}:${XUI_PORT}${Reset}"
    else
        echo -e "${Error} X-UI 启动失败，查看日志: $XUI_LOG"
    fi
}

# ==================== 停止 X-UI ====================
stop_xui() {
    echo -e "${Info} 停止 X-UI..."
    stop_process "x-ui"
}

# ==================== 重启 X-UI ====================
restart_xui() {
    echo -e "${Info} 重启 X-UI..."
    stop_xui
    sleep 2
    start_xui
}

# ==================== 查看状态 ====================
status_xui() {
    echo -e "${Info} X-UI 状态:"
    status_process "x-ui"
    
    if [ -f "$XUI_DIR/config.json" ]; then
        local port=$(grep -o '"webPort":[0-9]*' "$XUI_DIR/config.json" | cut -d: -f2)
        echo -e ""
        echo -e "面板端口: ${Cyan}${port:-未知}${Reset}"
        echo -e "访问地址: ${Cyan}http://${PUBLIC_IP:-YOUR_IP}:${port:-54321}${Reset}"
    fi
}

# ==================== 卸载 X-UI ====================
uninstall_xui() {
    echo -e "${Warning} 确定要卸载 X-UI? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_xui
    rm -rf "$XUI_DIR"
    echo -e "${Info} X-UI 已卸载"
}

# ==================== 查看日志 ====================
view_log() {
    if [ -f "$XUI_LOG" ]; then
        echo -e "${Info} X-UI 日志 (最后 50 行):"
        tail -50 "$XUI_LOG"
    else
        echo -e "${Warning} 日志文件不存在"
    fi
}

# ==================== 修改设置 ====================
modify_settings() {
    echo -e ""
    echo -e "${Green}==================== 修改设置 ====================${Reset}"
    echo -e " ${Green}1.${Reset}  修改端口"
    echo -e " ${Green}2.${Reset}  修改用户名/密码"
    echo -e " ${Green}3.${Reset}  重置所有设置"
    echo -e " ${Green}0.${Reset}  返回"
    echo -e "${Green}=================================================${Reset}"
    
    read -p " 请选择 [0-3]: " choice
    
    case "$choice" in
        1)
            read -p "新的面板端口: " new_port
            if [ -n "$new_port" ]; then
                sed -i "s/\"webPort\":[0-9]*/\"webPort\":$new_port/" "$XUI_DIR/config.json"
                echo -e "${Info} 端口已修改为 $new_port，请重启生效"
            fi
            ;;
        2)
            read -p "新用户名: " new_user
            read -p "新密码: " new_pass
            if [ -n "$new_user" ] && [ -n "$new_pass" ]; then
                sed -i "s/\"username\":\"[^\"]*\"/\"username\":\"$new_user\"/" "$XUI_DIR/config.json"
                sed -i "s/\"password\":\"[^\"]*\"/\"password\":\"$new_pass\"/" "$XUI_DIR/config.json"
                echo -e "${Info} 用户名/密码已修改，请重启生效"
            fi
            ;;
        3)
            echo -e "${Warning} 这将删除所有配置"
            read -p "确定? [y/N]: " confirm
            [[ $confirm =~ ^[Yy]$ ]] && rm -f "$XUI_DIR/config.json" "$XUI_DB"
            ;;
    esac
}

# ==================== 主菜单 ====================
show_xui_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦ ╦   ╦ ╦╦
    ╠╩╦╝───║ ║║
    ╩ ╩    ╚═╝╩
    可视化面板
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if [ -f "$XUI_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if status_process "x-ui" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== X-UI 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  安装 X-UI"
        echo -e " ${Green}2.${Reset}  卸载 X-UI"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  启动"
        echo -e " ${Green}4.${Reset}  停止"
        echo -e " ${Green}5.${Reset}  重启"
        echo -e " ${Green}6.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  查看日志"
        echo -e " ${Green}8.${Reset}  修改设置"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-8]: " choice
        
        case "$choice" in
            1) install_xui ;;
            2) uninstall_xui ;;
            3) start_xui ;;
            4) stop_xui ;;
            5) restart_xui ;;
            6) status_xui ;;
            7) view_log ;;
            8) modify_settings ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
main() {
    init_xui
    show_xui_menu
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
