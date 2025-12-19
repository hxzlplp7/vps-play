#!/bin/bash
# VPS 测评模块 - VPS-play
# 集成多种 VPS 测评脚本
# 支持: Linux, FreeBSD, Serv00/Hostuno

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/benchmark"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"

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
BENCH_DIR="$HOME/.vps-play/benchmark"
mkdir -p "$BENCH_DIR"

# 检测环境
is_serv00=false
is_freebsd=false
has_root=false

detect_bench_env() {
    # 检测 Serv00/Hostuno
    command -v devil &>/dev/null && is_serv00=true
    hostname 2>/dev/null | grep -qiE "serv00|hostuno" && is_serv00=true
    
    # 检测 FreeBSD
    [ "$(uname)" = "FreeBSD" ] && is_freebsd=true
    
    # 检测 root
    [ "$(id -u)" = "0" ] && has_root=true
}

# ==================== 融合怪 (ECS) ====================
run_ecs() {
    echo -e "${Info} 融合怪 VPS 测评脚本"
    echo -e "${Tip} 来源: github.com/spiritLHLS/ecs"
    echo -e ""
    
    if [ "$is_serv00" = true ]; then
        echo -e "${Warning} Serv00 环境检测"
        echo -e "${Tip} 推荐使用 Go 版本 (无需 root，更稳定)"
        echo -e ""
        echo -e " ${Green}1.${Reset} 使用 Go 版本 (推荐)"
        echo -e " ${Green}2.${Reset} 尝试 Shell 版本 (可能不完整)"
        echo -e " ${Green}0.${Reset} 返回"
        echo -e ""
        read -p "请选择 [0-2]: " ecs_choice
        
        case "$ecs_choice" in
            1) run_ecs_go ;;
            2) run_ecs_shell ;;
            0) return ;;
        esac
    else
        echo -e " ${Green}1.${Reset} 完整测试 (推荐)"
        echo -e " ${Green}2.${Reset} 精简测试"
        echo -e " ${Green}3.${Reset} 仅 IP 质量检测"
        echo -e " ${Green}4.${Reset} Go 版本 (无需依赖)"
        echo -e " ${Green}0.${Reset} 返回"
        echo -e ""
        read -p "请选择 [0-4]: " ecs_choice
        
        case "$ecs_choice" in
            1) run_ecs_shell "-m 1" ;;
            2) run_ecs_shell "-m 2" ;;
            3) run_ecs_ipcheck ;;
            4) run_ecs_go ;;
            0) return ;;
        esac
    fi
}

run_ecs_shell() {
    local params="${1:-}"
    echo -e "${Info} 下载并运行融合怪..."
    
    cd "$BENCH_DIR"
    
    if curl -sL https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh; then
        chmod +x ecs.sh
        if [ -n "$params" ]; then
            bash ecs.sh $params
        else
            bash ecs.sh
        fi
    else
        echo -e "${Error} 下载失败，尝试备用源..."
        bash <(wget -qO- bash.spiritlhl.net/ecs) $params
    fi
}

run_ecs_go() {
    echo -e "${Info} Go 版本融合怪 (goecs)"
    echo -e "${Tip} 来源: github.com/oneclickvirt/ecs"
    echo -e "${Tip} 特点: 无环境依赖，支持非 root，支持 FreeBSD"
    echo -e ""
    
    cd "$BENCH_DIR"
    
    # 下载 goecs.sh
    echo -e "${Info} 下载安装脚本..."
    
    local goecs_url="https://raw.githubusercontent.com/oneclickvirt/ecs/master/goecs.sh"
    local goecs_cdn="https://cdn.spiritlhl.net/https://raw.githubusercontent.com/oneclickvirt/ecs/master/goecs.sh"
    
    if curl -sL "$goecs_cdn" -o goecs.sh 2>/dev/null; then
        echo -e "${Info} 使用 CDN 加速下载成功"
    elif curl -sL "$goecs_url" -o goecs.sh 2>/dev/null; then
        echo -e "${Info} 下载成功"
    else
        echo -e "${Error} 下载失败"
        echo -e "${Tip} 请手动运行:"
        echo -e "  curl -L $goecs_url -o goecs.sh && chmod +x goecs.sh && ./goecs.sh install && goecs"
        return 1
    fi
    
    chmod +x goecs.sh
    
    # 检查是否已安装 goecs
    if command -v goecs &>/dev/null; then
        echo -e "${Info} goecs 已安装，直接运行..."
        goecs
    else
        echo -e "${Info} 安装 goecs..."
        export noninteractive=true
        ./goecs.sh install
        
        if command -v goecs &>/dev/null; then
            echo -e "${Info} 安装成功，运行测试..."
            goecs
        elif [ -f "$HOME/.local/bin/goecs" ]; then
            "$HOME/.local/bin/goecs"
        elif [ -f "/usr/local/bin/goecs" ]; then
            /usr/local/bin/goecs
        else
            echo -e "${Warning} goecs 未找到，尝试直接下载二进制文件..."
            run_ecs_go_direct
        fi
    fi
}

# 直接下载二进制文件（备用方案）
run_ecs_go_direct() {
    local arch="amd64"
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7*) arch="arm" ;;
        i386|i686) arch="386" ;;
    esac
    
    local os="linux"
    [ "$(uname)" = "FreeBSD" ] && os="freebsd"
    
    local url="https://github.com/oneclickvirt/ecs/releases/latest/download/ecs_${os}_${arch}"
    
    echo -e "${Info} 下载二进制文件: ecs_${os}_${arch}"
    
    if curl -sL "$url" -o goecs_bin 2>/dev/null; then
        chmod +x goecs_bin
        ./goecs_bin
    else
        echo -e "${Error} 下载失败"
        echo -e "${Tip} 请访问 https://github.com/oneclickvirt/ecs/releases 手动下载"
    fi
}

run_ecs_ipcheck() {
    echo -e "${Info} IP 质量检测..."
    bash <(wget -qO- bash.spiritlhl.net/ecs-ipcheck)
}

# ==================== Serv00 专用测评 ====================
run_serv00_bench() {
    echo -e "${Cyan}"
    cat << "EOF"
    ╔═╗╔═╗╦═╗╦  ╦┌─┐┌─┐  ╔╗ ╔═╗╔╗╔╔═╗╦ ╦
    ╚═╗║╣ ╠╦╝╚╗╔╝│ ││ │  ╠╩╗║╣ ║║║║  ╠═╣
    ╚═╝╚═╝╩╚═ ╚╝ └─┘└─┘  ╚═╝╚═╝╝╚╝╚═╝╩ ╩
    Serv00/Hostuno 专用测评
EOF
    echo -e "${Reset}"
    
    echo -e "${Info} 开始 Serv00 环境测评..."
    echo -e ""
    
    # 基础信息
    echo -e "${Green}==================== 系统信息 ====================${Reset}"
    echo -e " 主机名:     $(hostname)"
    echo -e " 系统:       $(uname -s) $(uname -r)"
    echo -e " 架构:       $(uname -m)"
    echo -e " 用户:       $(whoami)"
    echo -e " 家目录:     $HOME"
    echo -e ""
    
    # 磁盘配额
    echo -e "${Green}==================== 磁盘配额 ====================${Reset}"
    if command -v quota &>/dev/null; then
        quota -h 2>/dev/null || echo -e " 无法获取配额信息"
    else
        df -h "$HOME" 2>/dev/null | tail -1
    fi
    echo -e ""
    
    # 内存信息
    echo -e "${Green}==================== 内存信息 ====================${Reset}"
    if [ -f /proc/meminfo ]; then
        grep -E "MemTotal|MemFree|MemAvailable" /proc/meminfo 2>/dev/null
    else
        # FreeBSD
        sysctl -n hw.physmem 2>/dev/null | awk '{print " 物理内存: " $1/1024/1024/1024 " GB"}'
    fi
    echo -e ""
    
    # CPU 信息
    echo -e "${Green}==================== CPU 信息 ====================${Reset}"
    if [ -f /proc/cpuinfo ]; then
        grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2
    else
        sysctl -n hw.model 2>/dev/null
    fi
    sysctl -n hw.ncpu 2>/dev/null && echo -e " CPU 核心: $(sysctl -n hw.ncpu)"
    echo -e ""
    
    # 网络信息
    echo -e "${Green}==================== 网络信息 ====================${Reset}"
    local ipv4=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null)
    local ipv6=$(curl -s6m5 ip.sb 2>/dev/null)
    
    echo -e " IPv4:       ${Cyan}${ipv4:-无}${Reset}"
    echo -e " IPv6:       ${Cyan}${ipv6:-无}${Reset}"
    echo -e ""
    
    # 端口信息
    echo -e "${Green}==================== 端口信息 ====================${Reset}"
    if command -v devil &>/dev/null; then
        devil port list 2>/dev/null | head -20
    else
        echo -e " 无法获取端口信息 (需要 devil 命令)"
    fi
    echo -e ""
    
    # 网络连通性
    echo -e "${Green}==================== 网络连通性 ====================${Reset}"
    echo -n " Google:     "
    if curl -sIm3 https://www.google.com &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
    
    echo -n " GitHub:     "
    if curl -sIm3 https://github.com &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
    
    echo -n " Cloudflare: "
    if curl -sIm3 https://www.cloudflare.com &>/dev/null; then
        echo -e "${Green}可访问${Reset}"
    else
        echo -e "${Red}不可访问${Reset}"
    fi
    echo -e ""
    
    # 简单速度测试
    echo -e "${Green}==================== 下载速度测试 ====================${Reset}"
    echo -e "${Info} 测试中 (下载 10MB 文件)..."
    
    local start_time=$(date +%s.%N)
    curl -sL -o /dev/null "https://speed.cloudflare.com/__down?bytes=10485760" 2>/dev/null
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    if [ "$duration" != "0" ] && [ -n "$duration" ]; then
        local speed=$(echo "10 / $duration" | bc 2>/dev/null || echo "N/A")
        echo -e " Cloudflare: ${Cyan}${speed} MB/s${Reset}"
    else
        echo -e " 速度测试失败"
    fi
    echo -e ""
    
    echo -e "${Green}==================== 测评完成 ====================${Reset}"
}

# ==================== 其他测评脚本 ====================
run_bench_sh() {
    echo -e "${Info} 运行 bench.sh..."
    curl -sL https://raw.githubusercontent.com/teddysun/across/master/bench.sh | bash
}

run_superbench() {
    echo -e "${Info} 运行 SuperBench..."
    bash <(curl -sL https://raw.githubusercontent.com/oooldking/script/master/superbench.sh)
}

run_yabs() {
    echo -e "${Info} 运行 YABS..."
    curl -sL yabs.sh | bash
}

run_speedtest() {
    echo -e "${Info} 网络速度测试..."
    
    if [ "$is_serv00" = true ]; then
        echo -e "${Warning} Serv00 环境可能无法安装 speedtest-cli"
        echo -e "${Tip} 使用简化的速度测试..."
        
        echo -e ""
        echo -e "${Info} Cloudflare 下载测试 (10MB)..."
        time curl -sL -o /dev/null "https://speed.cloudflare.com/__down?bytes=10485760" 2>&1
        
        echo -e ""
        echo -e "${Info} Cloudflare 上传测试 (1MB)..."
        dd if=/dev/zero bs=1M count=1 2>/dev/null | curl -sL -X POST -d @- "https://speed.cloudflare.com/__up" -o /dev/null 2>&1
    else
        # 尝试使用 speedtest-cli
        if command -v speedtest-cli &>/dev/null; then
            speedtest-cli
        elif command -v speedtest &>/dev/null; then
            speedtest
        else
            echo -e "${Warning} speedtest 未安装，使用备用方案"
            bash <(curl -sL https://raw.githubusercontent.com/spiritLHLS/ecsspeed/main/script/ecsspeed.sh)
        fi
    fi
}

run_traceroute() {
    echo -e "${Info} 回程路由测试..."
    
    if [ "$is_serv00" = true ]; then
        echo -e "${Warning} Serv00 可能不支持完整回程测试"
        echo -e "${Tip} 使用简化测试..."
        
        read -p "输入目标 IP (默认: 114.114.114.114): " target_ip
        target_ip=${target_ip:-114.114.114.114}
        
        if command -v traceroute &>/dev/null; then
            traceroute -m 20 "$target_ip"
        else
            echo -e "${Error} traceroute 不可用"
        fi
    else
        # 使用 NextTrace
        curl -sL https://github.com/nxtrace/NTrace-core/raw/main/AutoTrace.sh | bash
    fi
}

# ==================== 主菜单 ====================
show_bench_menu() {
    detect_bench_env
    
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦  ╦╔═╗╔═╗  ╔╗ ╔═╗╔╗╔╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗  ╠╩╗║╣ ║║║║  ╠═╣
     ╚╝ ╩  ╚═╝  ╚═╝╚═╝╝╚╝╚═╝╩ ╩
    VPS 测评工具
EOF
        echo -e "${Reset}"
        
        # 显示环境信息
        if [ "$is_serv00" = true ]; then
            echo -e " 环境: ${Yellow}Serv00/Hostuno${Reset} (部分功能受限)"
        elif [ "$is_freebsd" = true ]; then
            echo -e " 环境: ${Cyan}FreeBSD${Reset}"
        else
            echo -e " 环境: ${Green}Linux${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== 测评脚本 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  融合怪 (ECS) - 综合测评"
        echo -e " ${Green}2.${Reset}  IP 质量检测"
        if [ "$is_serv00" = true ]; then
            echo -e " ${Green}3.${Reset}  ${Yellow}Serv00 专用测评${Reset}"
        else
            echo -e " ${Green}3.${Reset}  bench.sh - 经典测评"
        fi
        echo -e " ${Green}4.${Reset}  网络速度测试"
        echo -e " ${Green}5.${Reset}  回程路由测试"
        echo -e "${Green}---------------------------------------------------${Reset}"
        if [ "$is_serv00" != true ]; then
            echo -e " ${Green}6.${Reset}  SuperBench"
            echo -e " ${Green}7.${Reset}  YABS (Yet Another Bench Script)"
        fi
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-7]: " choice
        
        case "$choice" in
            1) run_ecs ;;
            2) run_ecs_ipcheck ;;
            3)
                if [ "$is_serv00" = true ]; then
                    run_serv00_bench
                else
                    run_bench_sh
                fi
                ;;
            4) run_speedtest ;;
            5) run_traceroute ;;
            6) 
                if [ "$is_serv00" != true ]; then
                    run_superbench
                else
                    echo -e "${Error} 无效选择"
                fi
                ;;
            7)
                if [ "$is_serv00" != true ]; then
                    run_yabs
                else
                    echo -e "${Error} 无效选择"
                fi
                ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 入口 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_bench_menu
fi
