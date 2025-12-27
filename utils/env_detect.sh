#!/bin/bash
# 环境检测工具 - VPS-play
# 检测系统类型、权限级别、网络环境等

# ==================== 全局变量 ====================
ENV_TYPE=""           # vps/natvps/freebsd/serv00
OS_TYPE=""            # linux/freebsd
OS_DISTRO=""          # ubuntu/debian/centos/alpine/freebsd
HAS_ROOT=false        # 是否有 root 权限
HAS_SYSTEMD=false     # 是否支持 systemd
HAS_OPENRC=false      # 是否支持 OpenRC (Alpine)
HAS_DEVIL=false       # 是否有 devil (Serv00/Hostuno)
IS_NAT=false          # 是否为 NAT 环境
PUBLIC_IP=""          # 公网 IP
LOCAL_IP=""           # 本地 IP
PKG_MANAGER=""        # 包管理器 (apt/yum/apk/pkg)

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

# ==================== 检测操作系统 ====================
detect_os() {
    local os=$(uname -s)
    
    case "$os" in
        Linux)
            OS_TYPE="linux"
            
            # 检测发行版
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
            elif [ -f /etc/redhat-release ]; then
                OS_DISTRO="centos"
            elif [ -f /etc/debian_version ]; then
                OS_DISTRO="debian"
            else
                OS_DISTRO="unknown"
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
    
    echo -e "${Info} 操作系统: $OS_TYPE ($OS_DISTRO)"
}

# ==================== 检测权限 ====================
detect_permissions() {
    if [ "$(id -u)" = "0" ]; then
        HAS_ROOT=true
        echo -e "${Info} 权限: ${Green}root${Reset}"
    else
        HAS_ROOT=false
        echo -e "${Warning} 权限: 非 root 用户 ($(whoami))"
        
        # 检测是否可以使用 sudo
        if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            echo -e "${Info} 检测到 sudo 权限"
            HAS_ROOT=true
        fi
    fi
}

# ==================== 检测系统服务 ====================
detect_services() {
    # 检测 systemd
    if command -v systemctl &>/dev/null && systemctl &>/dev/null; then
        HAS_SYSTEMD=true
        echo -e "${Info} 服务管理: ${Green}systemd${Reset}"
    # 检测 OpenRC (Alpine Linux)
    elif command -v rc-service &>/dev/null; then
        HAS_OPENRC=true
        echo -e "${Info} 服务管理: ${Green}OpenRC${Reset}"
    else
        HAS_SYSTEMD=false
        HAS_OPENRC=false
        echo -e "${Warning} 服务管理: 无 systemd/OpenRC (使用 cron/screen)"
    fi
    
    # 检测 devil (Serv00/Hostuno 特有)
    if command -v devil &>/dev/null; then
        HAS_DEVIL=true
        echo -e "${Info} 检测到 ${Cyan}devil${Reset} 命令 (Serv00/Hostuno 环境)"
    fi
    
    # 检测包管理器
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
    elif command -v pkg &>/dev/null; then
        PKG_MANAGER="pkg"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    else
        PKG_MANAGER="unknown"
    fi
    echo -e "${Info} 包管理器: ${Cyan}${PKG_MANAGER}${Reset}"
}

# ==================== 检测网络环境 ====================
detect_network() {
    echo -e "${Info} 检测网络环境..."
    
    # 获取公网 IP
    PUBLIC_IP=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null || echo "unknown")
    
    # 获取本地 IP
    if command -v hostname &>/dev/null; then
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "unknown")
    else
        LOCAL_IP="unknown"
    fi
    
    # 判断是否为 NAT 环境
    if [ "$PUBLIC_IP" != "$LOCAL_IP" ] && [ "$PUBLIC_IP" != "unknown" ] && [ "$LOCAL_IP" != "unknown" ]; then
        IS_NAT=true
        echo -e "${Warning} NAT 环境检测"
        echo -e "  公网 IP: ${Cyan}${PUBLIC_IP}${Reset}"
        echo -e "  本地 IP: ${Cyan}${LOCAL_IP}${Reset}"
    else
        IS_NAT=false
        echo -e "${Info} 公网 IP: ${Cyan}${PUBLIC_IP}${Reset}"
    fi
}

# ==================== 综合判断环境类型 ====================
determine_env_type() {
    if [ "$HAS_DEVIL" = true ]; then
        ENV_TYPE="serv00"
        echo -e "${Info} 环境类型: ${Yellow}Serv00/Hostuno${Reset}"
    elif [ "$OS_TYPE" = "freebsd" ]; then
        ENV_TYPE="freebsd"
        echo -e "${Info} 环境类型: ${Cyan}FreeBSD${Reset}"
    elif [ "$IS_NAT" = true ]; then
        ENV_TYPE="natvps"
        echo -e "${Info} 环境类型: ${Yellow}NAT VPS${Reset}"
    elif [ "$HAS_ROOT" = true ]; then
        ENV_TYPE="vps"
        echo -e "${Info} 环境类型: ${Green}VPS (完整权限)${Reset}"
    else
        ENV_TYPE="limited"
        echo -e "${Warning} 环境类型: ${Red}受限环境${Reset}"
    fi
}

# ==================== 检测架构 ====================
detect_arch() {
    local arch=$(uname -m)
    
    case $arch in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        i386|i686)
            ARCH="386"
            ;;
        *)
            ARCH="unknown"
            ;;
    esac
    
    echo -e "${Info} 架构: ${Cyan}${ARCH}${Reset}"
}

# ==================== 检测虚拟化 ====================
VIRT_TYPE=""
IS_CONTAINER=false

detect_virtualization() {
    # 检测是否为容器
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        VIRT_TYPE="docker"
        IS_CONTAINER=true
        echo -e "${Info} 虚拟化: ${Yellow}Docker 容器${Reset}"
        return
    fi
    
    if [ -f /run/.containerenv ]; then
        VIRT_TYPE="podman"
        IS_CONTAINER=true
        echo -e "${Info} 虚拟化: ${Yellow}Podman 容器${Reset}"
        return
    fi
    
    # 使用 systemd-detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null)
        if [ "$VIRT_TYPE" != "none" ] && [ -n "$VIRT_TYPE" ]; then
            case "$VIRT_TYPE" in
                kvm)
                    echo -e "${Info} 虚拟化: ${Cyan}KVM${Reset}"
                    ;;
                vmware)
                    echo -e "${Info} 虚拟化: ${Cyan}VMware${Reset}"
                    ;;
                xen)
                    echo -e "${Info} 虚拟化: ${Cyan}Xen${Reset}"
                    ;;
                microsoft|hyperv)
                    VIRT_TYPE="hyper-v"
                    echo -e "${Info} 虚拟化: ${Cyan}Hyper-V${Reset}"
                    ;;
                oracle|virtualbox)
                    VIRT_TYPE="virtualbox"
                    echo -e "${Info} 虚拟化: ${Cyan}VirtualBox${Reset}"
                    ;;
                lxc|lxc-libvirt)
                    VIRT_TYPE="lxc"
                    IS_CONTAINER=true
                    echo -e "${Info} 虚拟化: ${Yellow}LXC 容器${Reset}"
                    ;;
                openvz)
                    VIRT_TYPE="openvz"
                    IS_CONTAINER=true
                    echo -e "${Info} 虚拟化: ${Yellow}OpenVZ${Reset}"
                    ;;
                *)
                    echo -e "${Info} 虚拟化: ${Cyan}${VIRT_TYPE}${Reset}"
                    ;;
            esac
            return
        fi
    fi
    
    # 备用检测方法
    if [ -f /sys/class/dmi/id/product_name ]; then
        local product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        case "$product" in
            *"Virtual Machine"*|*"Hyper-V"*)
                VIRT_TYPE="hyper-v"
                echo -e "${Info} 虚拟化: ${Cyan}Hyper-V${Reset}"
                return
                ;;
            *"VMware"*)
                VIRT_TYPE="vmware"
                echo -e "${Info} 虚拟化: ${Cyan}VMware${Reset}"
                return
                ;;
            *"VirtualBox"*)
                VIRT_TYPE="virtualbox"
                echo -e "${Info} 虚拟化: ${Cyan}VirtualBox${Reset}"
                return
                ;;
            *"KVM"*|*"QEMU"*)
                VIRT_TYPE="kvm"
                echo -e "${Info} 虚拟化: ${Cyan}KVM/QEMU${Reset}"
                return
                ;;
        esac
    fi
    
    # 检查 /proc/cpuinfo
    if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
        VIRT_TYPE="unknown-vm"
        echo -e "${Info} 虚拟化: ${Cyan}虚拟机 (类型未知)${Reset}"
        return
    fi
    
    # 物理机
    VIRT_TYPE="none"
    echo -e "${Info} 虚拟化: ${Green}物理机 / 无虚拟化${Reset}"
}

# ==================== 主函数 ====================
detect_environment() {
    echo -e ""
    echo -e "${Green}==================== 环境检测 ====================${Reset}"
    
    detect_os
    detect_arch
    detect_virtualization
    detect_permissions
    detect_services
    detect_network
    determine_env_type
    
    echo -e "${Green}=================================================${Reset}"
    echo -e ""
    
    # 导出环境变量
    export ENV_TYPE OS_TYPE OS_DISTRO ARCH HAS_ROOT HAS_SYSTEMD HAS_OPENRC HAS_DEVIL IS_NAT PUBLIC_IP LOCAL_IP VIRT_TYPE IS_CONTAINER PKG_MANAGER
}

# ==================== 保存环境信息 ====================
save_env_info() {
    local config_file="${1:-$HOME/.vps-play/env.conf}"
    
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
# VPS-play 环境配置
# 自动生成于 $(date)

ENV_TYPE="$ENV_TYPE"
OS_TYPE="$OS_TYPE"
OS_DISTRO="$OS_DISTRO"
ARCH="$ARCH"
HAS_ROOT="$HAS_ROOT"
HAS_SYSTEMD="$HAS_SYSTEMD"
HAS_OPENRC="$HAS_OPENRC"
HAS_DEVIL="$HAS_DEVIL"
IS_NAT="$IS_NAT"
PUBLIC_IP="$PUBLIC_IP"
LOCAL_IP="$LOCAL_IP"
VIRT_TYPE="$VIRT_TYPE"
IS_CONTAINER="$IS_CONTAINER"
PKG_MANAGER="$PKG_MANAGER"
EOF
    
    echo -e "${Info} 环境信息已保存到: $config_file"
}

# ==================== 加载环境信息 ====================
load_env_info() {
    local config_file="${1:-$HOME/.vps-play/env.conf}"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        echo -e "${Info} 环境信息已加载"
        return 0
    else
        echo -e "${Warning} 环境配置文件不存在，将重新检测"
        return 1
    fi
}

# ==================== 显示环境信息 ====================
show_env_info() {
    echo -e ""
    echo -e "${Green}==================== 当前环境 ====================${Reset}"
    echo -e " 环境类型: ${Yellow}${ENV_TYPE}${Reset}"
    echo -e " 操作系统: ${Cyan}${OS_TYPE} (${OS_DISTRO})${Reset}"
    echo -e " 架构:     ${Cyan}${ARCH}${Reset}"
    echo -e " 虚拟化:   ${Cyan}${VIRT_TYPE:-未知}${Reset}"
    [ "$IS_CONTAINER" = true ] && echo -e " 容器环境: ${Yellow}是${Reset}"
    echo -e " Root权限: $([ "$HAS_ROOT" = true ] && echo "${Green}是${Reset}" || echo "${Red}否${Reset}")"
    echo -e " Systemd:  $([ "$HAS_SYSTEMD" = true ] && echo "${Green}是${Reset}" || echo "${Red}否${Reset}")"
    echo -e " OpenRC:   $([ "$HAS_OPENRC" = true ] && echo "${Green}是${Reset}" || echo "${Red}否${Reset}")"
    echo -e " Devil:    $([ "$HAS_DEVIL" = true ] && echo "${Green}是${Reset}" || echo "${Red}否${Reset}")"
    echo -e " 包管理:  ${Cyan}${PKG_MANAGER}${Reset}"
    echo -e " NAT环境:  $([ "$IS_NAT" = true ] && echo "${Yellow}是${Reset}" || echo "${Green}否${Reset}")"
    echo -e " 公网IP:   ${Cyan}${PUBLIC_IP}${Reset}"
    [ "$IS_NAT" = true ] && echo -e " 本地IP:   ${Cyan}${LOCAL_IP}${Reset}"
    echo -e "${Green}=================================================${Reset}"
    echo -e ""
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_environment
    show_env_info
    save_env_info
fi

# ==================== 通用包安装函数 ====================
# 用法: install_package curl wget openssl
install_package() {
    local packages="$@"
    
    if [ -z "$packages" ]; then
        echo -e "${Warning} 未指定要安装的包"
        return 1
    fi
    
    # 如果没有 root 权限，尝试使用 sudo
    local SUDO=""
    if [ "$HAS_ROOT" != true ]; then
        if command -v sudo &>/dev/null; then
            SUDO="sudo"
        else
            echo -e "${Warning} 需要 root 权限来安装软件包"
            return 1
        fi
    fi
    
    echo -e "${Info} 安装软件包: $packages"
    
    case "$PKG_MANAGER" in
        apt)
            $SUDO apt-get update -qq
            $SUDO apt-get install -y -qq $packages
            ;;
        yum)
            $SUDO yum install -y -q $packages
            ;;
        dnf)
            $SUDO dnf install -y -q $packages
            ;;
        apk)
            $SUDO apk add --no-cache $packages
            ;;
        pkg)
            $SUDO pkg install -y $packages
            ;;
        pacman)
            $SUDO pacman -S --noconfirm $packages
            ;;
        *)
            echo -e "${Error} 不支持的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${Info} 软件包安装完成"
    else
        echo -e "${Error} 软件包安装失败"
        return 1
    fi
}

# ==================== 检查并安装依赖 ====================
# 用法: ensure_command curl "curl"
# 第一个参数是命令名，第二个参数是包名（可选，默认同命令名）
ensure_command() {
    local cmd="$1"
    local pkg="${2:-$1}"
    
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${Info} 正在安装 $pkg..."
        install_package "$pkg"
    fi
}
