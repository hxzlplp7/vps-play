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
    
    # 如果是 FreeBSD 且非 Root，强制视为 Serv00 模式（受限环境）
    if [ "$is_freebsd" = true ] && [ "$has_root" = false ]; then
        is_serv00=true
    fi
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
    echo -e "${Tip} 特点: 无环境依赖，支持非 root，自动适配架构"
    echo -e ""
    
    cd "$BENCH_DIR"
    
    # 清理旧文件
    rm -f goecs goecs.sh goecs_*.zip
    
    # 1. 确定架构和系统
    local os="linux"
    [ "$(uname)" = "FreeBSD" ] && os="freebsd"
    
    local arch="amd64"
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7*) arch="arm" ;;
    esac
    
    local filename="goecs_${os}_${arch}"
    
    # 2. 尝试下载 (包括 CDN)
    echo -e "${Info} 正在下载 ${filename}.zip ..."
    
    local download_success=false
    local urls=(
        "https://cdn.spiritlhl.net/https://github.com/oneclickvirt/ecs/releases/latest/download/${filename}.zip"
        "https://github.com/oneclickvirt/ecs/releases/latest/download/${filename}.zip"
    )
    
    for url in "${urls[@]}"; do
        if curl -sL "$url" -o "${filename}.zip"; then
            # 检查文件是否为有效的 zip (检查前几个字节)
            if head -c 4 "${filename}.zip" | grep -q "PK"; then
                download_success=true
                echo -e "${Info} 下载成功"
                break
            fi
        fi
    done
    
    if [ "$download_success" = false ]; then
        echo -e "${Error} 下载失败，请检查网络连接"
        return 1
    fi
    
    # 3. 解压
    echo -e "${Info} 正在解压..."
    local unzip_success=false
    
    if command -v unzip &>/dev/null; then
        unzip -o "${filename}.zip" >/dev/null && unzip_success=true
    elif command -v python3 &>/dev/null; then
        python3 -m zipfile -e "${filename}.zip" . && unzip_success=true
    else
        echo -e "${Error} 未找到 unzip 或 python3，无法解压"
        return 1
    fi
    
    if [ "$unzip_success" = true ]; then
        # 4. 运行
        if [ -f "goecs" ]; then
            chmod +x goecs
            
            # 在 Serv00 上可能需要设置一些环境变量
            echo -e "${Info} 启动 goecs..."
            echo -e "${Tip} 如果遇到权限问题，请确保在自己的目录下运行"
            echo -e ""
            
            # 使用 ./goecs 运行
            ./goecs
        else
            echo -e "${Error} 解压后未找到 goecs 二进制文件"
        fi
    else
        echo -e "${Error} 解压失败"
    fi
    
    # 清理
    rm -f "${filename}.zip"
}

# 移除旧的 direct 函数，因为已经合并
# run_ecs_go_direct() { ... }

run_ecs_ipcheck() {
    echo -e "${Info} IP 质量检测..."
    
    if [ "$is_serv00" = true ]; then
        echo -e "${Warning} Serv00 进程数受限，使用简化检测..."
        echo -e ""
        run_simple_ipcheck
    else
        bash <(wget -qO- bash.spiritlhl.net/ecs-ipcheck)
    fi
}

# Serv00 友好的简化 IP 检测
run_simple_ipcheck() {
    echo -e "${Green}==================== IP 信息 ====================${Reset}"
    
    # 获取 IP
    local ipv4=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null)
    local ipv6=$(curl -s6m5 ip.sb 2>/dev/null)
    
    echo -e " IPv4: ${Cyan}${ipv4:-无}${Reset}"
    echo -e " IPv6: ${Cyan}${ipv6:-无}${Reset}"
    echo -e ""
    
    if [ -n "$ipv4" ]; then
        # IP 地理位置
        echo -e "${Green}==================== IP 地理位置 ====================${Reset}"
        local ip_info=$(curl -sm5 "https://ipapi.co/${ipv4}/json/" 2>/dev/null)
        if [ -n "$ip_info" ]; then
            local country=$(echo "$ip_info" | grep -o '"country_name":"[^"]*"' | cut -d'"' -f4)
            local city=$(echo "$ip_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
            local org=$(echo "$ip_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
            local asn=$(echo "$ip_info" | grep -o '"asn":"[^"]*"' | cut -d'"' -f4)
            
            echo -e " 国家: ${Cyan}${country:-未知}${Reset}"
            echo -e " 城市: ${Cyan}${city:-未知}${Reset}"
            echo -e " ASN:  ${Cyan}${asn:-未知}${Reset}"
            echo -e " 组织: ${Cyan}${org:-未知}${Reset}"
        fi
        echo -e ""
        
        # WARP 状态
        echo -e "${Green}==================== WARP 状态 ====================${Reset}"
        local warp=$(curl -sm5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "warp=" | cut -d= -f2)
        case "$warp" in
            on) echo -e " WARP: ${Green}已启用${Reset}" ;;
            plus) echo -e " WARP: ${Green}WARP+ 已启用${Reset}" ;;
            off) echo -e " WARP: ${Yellow}未启用${Reset}" ;;
            *) echo -e " WARP: ${Red}检测失败${Reset}" ;;
        esac
        echo -e ""
        
        # 简单连通性测试
        echo -e "${Green}==================== 连通性测试 ====================${Reset}"
        echo -n " Google:   "
        curl -sIm3 https://www.google.com &>/dev/null && echo -e "${Green}可访问${Reset}" || echo -e "${Red}不可访问${Reset}"
        
        echo -n " YouTube:  "
        curl -sIm3 https://www.youtube.com &>/dev/null && echo -e "${Green}可访问${Reset}" || echo -e "${Red}不可访问${Reset}"
        
        echo -n " ChatGPT:  "
        curl -sIm3 https://chat.openai.com &>/dev/null && echo -e "${Green}可访问${Reset}" || echo -e "${Red}不可访问${Reset}"
        
        echo -n " Netflix:  "
        local nf=$(curl -sLm5 "https://www.netflix.com/title/81215567" 2>/dev/null)
        if echo "$nf" | grep -q "NSEZ-403"; then
            echo -e "${Red}未解锁${Reset}"
        elif echo "$nf" | grep -qE "page-title|Netflix"; then
            echo -e "${Green}已解锁${Reset}"
        else
            echo -e "${Yellow}检测超时${Reset}"
        fi
        echo -e ""
    fi
    
    echo -e "${Green}=================================================${Reset}"
    echo -e "${Tip} 完整检测请在有 root 权限的 VPS 上运行"
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
    curl -sL https://yabs.sh | bash
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
    echo -e ""
    
    if [ "$is_serv00" = true ]; then
        echo -e "${Warning} Serv00 可能不支持完整回程测试"
        echo -e "${Tip} 使用简化测试..."
        echo -e ""
        
        read -p "输入目标 IP (默认: 114.114.114.114): " target_ip
        target_ip=${target_ip:-114.114.114.114}
        
        if command -v traceroute &>/dev/null; then
            traceroute -m 20 "$target_ip"
        else
            echo -e "${Error} traceroute 不可用"
        fi
    else
        echo -e " ${Green}1.${Reset} NextTrace (推荐)"
        echo -e " ${Green}2.${Reset} 融合怪回程测试"
        echo -e " ${Green}3.${Reset} 简单 traceroute"
        echo -e " ${Green}0.${Reset} 返回"
        echo -e ""
        read -p "请选择 [0-3]: " trace_choice
        
        case "$trace_choice" in
            1)
                # NextTrace 官方安装
                echo -e "${Info} 安装 NextTrace..."
                if command -v nexttrace &>/dev/null; then
                    echo -e "${Info} NextTrace 已安装"
                else
                    # 使用官方安装脚本
                    curl -Ls https://nxtrace.org/nt | bash 2>/dev/null || \
                    bash <(curl -Ls https://raw.githubusercontent.com/nxtrace/NTrace-core/main/nt_install.sh) 2>/dev/null
                fi
                
                if command -v nexttrace &>/dev/null; then
                    echo -e ""
                    read -p "输入目标 IP (默认: 114.114.114.114): " target_ip
                    target_ip=${target_ip:-114.114.114.114}
                    nexttrace "$target_ip"
                else
                    echo -e "${Error} NextTrace 安装失败"
                    echo -e "${Tip} 请手动安装: curl -Ls https://nxtrace.org/nt | bash"
                fi
                ;;
            2)
                # 使用融合怪的回程测试
                echo -e "${Info} 使用融合怪回程测试..."
                cd "$BENCH_DIR"
                curl -sL https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh 2>/dev/null
                if [ -f ecs.sh ]; then
                    chmod +x ecs.sh
                    bash ecs.sh -m 4
                else
                    echo -e "${Error} 下载失败"
                fi
                ;;
            3)
                read -p "输入目标 IP (默认: 114.114.114.114): " target_ip
                target_ip=${target_ip:-114.114.114.114}
                traceroute -m 30 "$target_ip" 2>/dev/null || \
                tracepath "$target_ip" 2>/dev/null || \
                echo -e "${Error} traceroute/tracepath 不可用"
                ;;
            0)
                return
                ;;
        esac
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
        echo -e " 模块版本: ${Green}v1.1${Reset}"
        
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
