#!/bin/bash
# WARP 模块 - VPS-play
# Cloudflare WARP 代理管理
# 参考: ygkkk/CFwarp, fscarmen/warp

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/warp"
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
WARP_DIR="$HOME/.vps-play/warp"
WGCF_BIN="$WARP_DIR/wgcf"
WGCF_ACCOUNT="$WARP_DIR/wgcf-account.toml"
WGCF_PROFILE="$WARP_DIR/wgcf-profile.conf"
WARP_CONF="/etc/wireguard/wgcf.conf"

mkdir -p "$WARP_DIR"

# wgcf 版本
WGCF_VERSION="2.2.22"

# ==================== 系统检测 ====================
check_system() {
    if [ -z "$OS_TYPE" ]; then
        case "$(uname -s)" in
            Linux) OS_TYPE="linux" ;;
            FreeBSD) OS_TYPE="freebsd" ;;
        esac
    fi
    
    if [ -z "$ARCH" ]; then
        case "$(uname -m)" in
            x86_64|amd64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            armv7l) ARCH="armv7" ;;
        esac
    fi
    
    # 检测发行版
    if [ -z "$OS_DISTRO" ] && [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    fi
}

# ==================== 获取 IP ====================
get_ipv4() {
    curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo ""
}

get_ipv6() {
    curl -s6m5 ip.sb 2>/dev/null || curl -s6m5 ifconfig.me 2>/dev/null || echo ""
}

show_ip() {
    echo -e "${Info} 当前 IP 信息:"
    local ipv4=$(get_ipv4)
    local ipv6=$(get_ipv6)
    
    [ -n "$ipv4" ] && echo -e " IPv4: ${Cyan}${ipv4}${Reset}" || echo -e " IPv4: ${Red}无${Reset}"
    [ -n "$ipv6" ] && echo -e " IPv6: ${Cyan}${ipv6}${Reset}" || echo -e " IPv6: ${Red}无${Reset}"
    
    # 检测 WARP 状态
    local warp_status=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep warp | cut -d= -f2)
    case "$warp_status" in
        on) echo -e " WARP: ${Green}已启用${Reset}" ;;
        plus) echo -e " WARP: ${Green}WARP+ 已启用${Reset}" ;;
        off) echo -e " WARP: ${Yellow}未启用${Reset}" ;;
        *) echo -e " WARP: ${Red}检测失败${Reset}" ;;
    esac
}

# ==================== 安装依赖 ====================
install_deps() {
    echo -e "${Info} 安装依赖..."
    
    case "$OS_DISTRO" in
        debian|ubuntu)
            apt-get update
            apt-get install -y curl wget wireguard-tools
            ;;
        centos|rhel|rocky|alma)
            yum install -y epel-release
            yum install -y curl wget wireguard-tools
            ;;
        fedora)
            dnf install -y curl wget wireguard-tools
            ;;
        alpine)
            apk add curl wget wireguard-tools
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm curl wget wireguard-tools
            ;;
        freebsd)
            pkg install -y curl wget wireguard
            ;;
        *)
            echo -e "${Warning} 未知系统，请手动安装 wireguard-tools"
            ;;
    esac
}

# ==================== 下载 wgcf ====================
download_wgcf() {
    echo -e "${Info} 下载 wgcf v${WGCF_VERSION}..."
    
    local os_type="linux"
    [ "$OS_TYPE" = "freebsd" ] && os_type="freebsd"
    
    local arch_type="amd64"
    case "$ARCH" in
        arm64) arch_type="arm64" ;;
        armv7) arch_type="armv7" ;;
    esac
    
    local url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_${os_type}_${arch_type}"
    
    if curl -sL "$url" -o "$WGCF_BIN"; then
        chmod +x "$WGCF_BIN"
        echo -e "${Info} wgcf 下载完成"
        return 0
    else
        echo -e "${Error} wgcf 下载失败"
        return 1
    fi
}

# ==================== 注册 WARP ====================
register_warp() {
    if [ ! -f "$WGCF_BIN" ]; then
        echo -e "${Error} 请先下载 wgcf"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    if [ -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Warning} 已存在 WARP 账户"
        read -p "重新注册? [y/N]: " re_reg
        [[ ! $re_reg =~ ^[Yy]$ ]] && return 0
        rm -f "$WGCF_ACCOUNT"
    fi
    
    echo -e "${Info} 注册 WARP 账户..."
    
    # 注册 (最多重试5次)
    local retry=0
    while [ $retry -lt 5 ]; do
        if $WGCF_BIN register --accept-tos 2>/dev/null; then
            echo -e "${Info} 注册成功"
            return 0
        fi
        retry=$((retry + 1))
        echo -e "${Warning} 注册失败，重试 $retry/5..."
        sleep 2
    done
    
    echo -e "${Error} 注册失败，请检查网络"
    return 1
}

# ==================== 生成配置 ====================
generate_config() {
    if [ ! -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Error} 请先注册 WARP 账户"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 生成 WireGuard 配置..."
    
    if $WGCF_BIN generate 2>/dev/null; then
        echo -e "${Info} 配置生成成功"
        
        # 优化配置
        optimize_config
        
        return 0
    else
        echo -e "${Error} 配置生成失败"
        return 1
    fi
}

# ==================== 优化配置 ====================
optimize_config() {
    if [ ! -f "$WGCF_PROFILE" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e ""
    echo -e "${Info} 选择 WARP 模式:"
    echo -e " ${Green}1.${Reset} 仅 IPv4 (推荐大多数用户)"
    echo -e " ${Green}2.${Reset} 仅 IPv6"
    echo -e " ${Green}3.${Reset} 双栈 IPv4 + IPv6"
    echo -e " ${Green}4.${Reset} 非全局 (仅特定IP走WARP)"
    
    read -p "请选择 [1-4, 默认1]: " mode
    mode=${mode:-1}
    
    case "$mode" in
        1)
            # 仅IPv4
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为 IPv4 模式"
            ;;
        2)
            # 仅IPv6
            sed -i 's/AllowedIPs = .*/AllowedIPs = ::\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为 IPv6 模式"
            ;;
        3)
            # 双栈
            sed -i 's/AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0, ::\/0/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为双栈模式"
            ;;
        4)
            # 非全局 - 仅 Cloudflare IP 走 WARP
            sed -i 's/AllowedIPs = .*/AllowedIPs = 1.1.1.1\/32, 1.0.0.1\/32, 2606:4700:4700::1111\/128, 2606:4700:4700::1001\/128/' "$WGCF_PROFILE"
            echo -e "${Info} 已设置为非全局模式"
            ;;
    esac
    
    # 添加 MTU 优化
    if ! grep -q "MTU" "$WGCF_PROFILE"; then
        sed -i '/\[Peer\]/i MTU = 1280' "$WGCF_PROFILE"
    fi
    
    # 添加 DNS
    if ! grep -q "DNS" "$WGCF_PROFILE"; then
        sed -i '/\[Interface\]/a DNS = 1.1.1.1, 2606:4700:4700::1111' "$WGCF_PROFILE"
    fi
    
    echo -e "${Info} 配置优化完成"
}

# ==================== 启动 WARP ====================
start_warp() {
    if [ ! -f "$WGCF_PROFILE" ]; then
        echo -e "${Error} 请先生成配置"
        return 1
    fi
    
    # 检查 WireGuard
    if ! command -v wg &>/dev/null; then
        echo -e "${Warning} WireGuard 未安装"
        install_deps
    fi
    
    echo -e "${Info} 启动 WARP..."
    
    # 复制配置到 WireGuard 目录
    if [ "$OS_TYPE" = "freebsd" ]; then
        mkdir -p /usr/local/etc/wireguard
        cp "$WGCF_PROFILE" /usr/local/etc/wireguard/wgcf.conf
        wg-quick up wgcf
    else
        mkdir -p /etc/wireguard
        cp "$WGCF_PROFILE" /etc/wireguard/wgcf.conf
        
        # 设置权限
        chmod 600 /etc/wireguard/wgcf.conf
        
        # 启动
        wg-quick up wgcf
        
        # 设置开机自启
        if command -v systemctl &>/dev/null; then
            systemctl enable wg-quick@wgcf 2>/dev/null
        fi
    fi
    
    sleep 2
    
    # 检查状态
    if wg show wgcf &>/dev/null; then
        echo -e "${Info} WARP 启动成功"
        show_ip
    else
        echo -e "${Error} WARP 启动失败"
    fi
}

# ==================== 停止 WARP ====================
stop_warp() {
    echo -e "${Info} 停止 WARP..."
    
    wg-quick down wgcf 2>/dev/null
    
    if command -v systemctl &>/dev/null; then
        systemctl disable wg-quick@wgcf 2>/dev/null
    fi
    
    echo -e "${Info} WARP 已停止"
}

# ==================== 重启 WARP ====================
restart_warp() {
    stop_warp
    sleep 1
    start_warp
}

# ==================== WARP 状态 ====================
status_warp() {
    echo -e "${Info} WARP 状态:"
    echo -e ""
    
    if wg show wgcf &>/dev/null 2>&1; then
        echo -e " 运行状态: ${Green}运行中${Reset}"
        echo -e ""
        wg show wgcf
    else
        echo -e " 运行状态: ${Red}未运行${Reset}"
    fi
    
    echo -e ""
    show_ip
}

# ==================== 卸载 WARP ====================
uninstall_warp() {
    echo -e "${Warning} 确定卸载 WARP? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_warp
    
    rm -f /etc/wireguard/wgcf.conf
    rm -f /usr/local/etc/wireguard/wgcf.conf
    rm -rf "$WARP_DIR"
    
    echo -e "${Info} WARP 已卸载"
}

# ==================== 一键安装 ====================
quick_install() {
    echo -e "${Info} 开始一键安装 WARP..."
    
    check_system
    install_deps || return 1
    download_wgcf || return 1
    register_warp || return 1
    generate_config || return 1
    start_warp
    
    echo -e ""
    echo -e "${Info} WARP 安装完成!"
}

# ==================== WARP+ 升级 ====================
upgrade_warp_plus() {
    echo -e "${Info} WARP+ 升级"
    echo -e "${Tip} 需要 WARP+ 许可证密钥"
    echo -e ""
    
    read -p "输入 WARP+ 许可证密钥: " license_key
    
    if [ -z "$license_key" ]; then
        echo -e "${Error} 密钥不能为空"
        return 1
    fi
    
    if [ ! -f "$WGCF_ACCOUNT" ]; then
        echo -e "${Error} 请先注册 WARP 账户"
        return 1
    fi
    
    cd "$WARP_DIR"
    
    echo -e "${Info} 升级到 WARP+..."
    
    if $WGCF_BIN update --license "$license_key" 2>/dev/null; then
        echo -e "${Info} WARP+ 升级成功"
        
        # 重新生成配置
        generate_config
        
        # 重启 WARP
        if wg show wgcf &>/dev/null 2>&1; then
            restart_warp
        fi
        
        return 0
    else
        echo -e "${Error} 升级失败，请检查许可证密钥"
        return 1
    fi
}

# ==================== 流媒体解锁检测 ====================
check_streaming() {
    echo -e "${Info} 检测流媒体解锁状态..."
    echo -e ""
    
    # Netflix
    echo -n " Netflix: "
    local nf=$(curl -sLm5 "https://www.netflix.com/title/81215567" 2>/dev/null)
    if echo "$nf" | grep -q "NSEZ-403"; then
        echo -e "${Red}未解锁${Reset}"
    elif echo "$nf" | grep -qE "page-title|Netflix"; then
        echo -e "${Green}已解锁${Reset}"
    else
        echo -e "${Yellow}检测超时${Reset}"
    fi
    
    # YouTube Premium
    echo -n " YouTube: "
    local yt=$(curl -sLm5 "https://www.youtube.com/premium" 2>/dev/null)
    if echo "$yt" | grep -q "Premium is not available"; then
        echo -e "${Red}无 Premium${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # ChatGPT
    echo -n " ChatGPT: "
    local gpt=$(curl -sLm5 "https://chat.openai.com/" -H "User-Agent: Mozilla/5.0" 2>/dev/null)
    if echo "$gpt" | grep -qE "Sorry|unavailable|blocked"; then
        echo -e "${Red}不可用${Reset}"
    else
        echo -e "${Green}可访问${Reset}"
    fi
    
    # Google
    echo -n " Google:  "
    if curl -sLm5 "https://www.google.com" &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
}

# ==================== 主菜单 ====================
show_warp_menu() {
    check_system
    
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦ ╦╔═╗╦═╗╔═╗
    ║║║╠═╣╠╦╝╠═╝
    ╚╩╝╩ ╩╩╚═╩  
    Cloudflare WARP
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if wg show wgcf &>/dev/null 2>&1; then
            echo -e " 状态: ${Green}运行中${Reset}"
        else
            echo -e " 状态: ${Yellow}未运行${Reset}"
        fi
        
        if [ -f "$WGCF_ACCOUNT" ]; then
            echo -e " 账户: ${Green}已注册${Reset}"
        else
            echo -e " 账户: ${Red}未注册${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== WARP 管理 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  一键安装 WARP"
        echo -e " ${Green}2.${Reset}  卸载 WARP"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}3.${Reset}  下载 wgcf"
        echo -e " ${Green}4.${Reset}  注册账户"
        echo -e " ${Green}5.${Reset}  生成配置"
        echo -e " ${Green}6.${Reset}  升级 WARP+"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}7.${Reset}  启动 WARP"
        echo -e " ${Green}8.${Reset}  停止 WARP"
        echo -e " ${Green}9.${Reset}  重启 WARP"
        echo -e " ${Green}10.${Reset} 查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}11.${Reset} 查看当前 IP"
        echo -e " ${Green}12.${Reset} 流媒体解锁检测"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-12]: " choice
        
        case "$choice" in
            1) quick_install ;;
            2) uninstall_warp ;;
            3) download_wgcf ;;
            4) register_warp ;;
            5) generate_config ;;
            6) upgrade_warp_plus ;;
            7) start_warp ;;
            8) stop_warp ;;
            9) restart_warp ;;
            10) status_warp ;;
            11) show_ip ;;
            12) check_streaming ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ "$0" = "bash" ]; then
    show_warp_menu
fi
