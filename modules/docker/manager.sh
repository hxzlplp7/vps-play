#!/bin/bash
# Docker 模块 - VPS-play
# 一键安装 Docker 和 Docker Compose
# 支持: Linux (Debian/Ubuntu/CentOS/Alpine) 和 FreeBSD

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/docker"
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
DOCKER_COMPOSE_VERSION="2.24.0"

# ==================== 检测 Docker ====================
check_docker() {
    if command -v docker &>/dev/null; then
        local version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        echo -e "${Info} Docker 已安装: ${Green}${version}${Reset}"
        return 0
    else
        echo -e "${Warning} Docker 未安装"
        return 1
    fi
}

check_docker_compose() {
    if command -v docker-compose &>/dev/null; then
        local version=$(docker-compose --version 2>/dev/null | awk '{print $4}' | tr -d ',')
        echo -e "${Info} Docker Compose (v1): ${Green}${version}${Reset}"
        return 0
    elif docker compose version &>/dev/null 2>&1; then
        local version=$(docker compose version 2>/dev/null | awk '{print $4}')
        echo -e "${Info} Docker Compose (v2): ${Green}${version}${Reset}"
        return 0
    else
        echo -e "${Warning} Docker Compose 未安装"
        return 1
    fi
}

# ==================== Linux 安装 ====================
install_docker_linux() {
    # 检查磁盘空间 (至少需要 500MB，推荐 1GB)
    local available_kb=$(df -k /var | awk 'NR==2 {print $4}')
    if [ "$available_kb" -lt 512000 ]; then
        echo -e "${Error} 磁盘空间严重不足!"
        echo -e "  当前可用: $(($available_kb/1024)) MB"
        echo -e "  需要至少: 500 MB (推荐 1GB)"
        echo -e "${Tip} 请尝试清理空间: sudo apt-get clean && sudo apt-get autoremove"
        return 1
    fi

    echo -e "${Info} 开始安装 Docker (Linux)..."
    
    # 检测发行版
    if [ -z "$OS_DISTRO" ]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        fi
    fi
    
    # 修正 raspbian
    if [ "$OS_DISTRO" = "raspbian" ]; then
        OS_DISTRO="debian"
    fi

    local install_status=0
    
    case "$OS_DISTRO" in
        debian|ubuntu|kali)
            install_docker_debian
            install_status=$?
            ;;
        centos|rhel|rocky|alma|fedora)
            install_docker_centos
            install_status=$?
            ;;
        alpine)
            install_docker_alpine
            install_status=$?
            ;;
        *)
            echo -e "${Warning} 未知发行版，尝试使用官方脚本安装"
            install_docker_script
            install_status=$?
            ;;
    esac
    
    if [ $install_status -eq 0 ]; then
        echo -e "${Info} Docker 安装完成"
        systemctl start docker 2>/dev/null
        systemctl enable docker 2>/dev/null
        check_docker
    else
        echo -e "${Error} Docker 安装失败，请检查上方错误信息"
        return 1
    fi
}

install_docker_debian() {
    echo -e "${Info} 使用 APT 安装 Docker ($OS_DISTRO)..."
    
    # 卸载旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # 安装依赖
    if ! apt-get update; then
        echo -e "${Error} apt-get update 失败"
        return 1
    fi
    
    if ! apt-get install -y ca-certificates curl gnupg lsb-release; then
        echo -e "${Error} 依赖包安装失败"
        return 1
    fi
    
    # 添加 Docker GPG key
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg
    if ! curl -fsSL https://download.docker.com/linux/$OS_DISTRO/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        echo -e "${Error} GPG Key 下载失败"
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 添加仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_DISTRO \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装
    if ! apt-get update; then
        echo -e "${Error} apt-get update (Docker repo) 失败"
        return 1
    fi
    
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        echo -e "${Error} Docker 软件包安装失败"
        return 1
    fi
    
    # 启动服务
    systemctl enable docker
    systemctl start docker
    return 0
}

install_docker_centos() {
    echo -e "${Info} 使用 YUM 安装 Docker (CentOS/RHEL)..."
    
    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # 安装 yum-utils
    yum install -y yum-utils
    
    # 添加仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动服务
    systemctl enable docker
    systemctl start docker
    
    echo -e "${Info} Docker 安装完成"
}

install_docker_alpine() {
    echo -e "${Info} 使用 APK 安装 Docker (Alpine)..."
    
    apk update
    apk add docker docker-cli-compose
    
    # 添加到开机启动
    rc-update add docker boot
    service docker start
    
    echo -e "${Info} Docker 安装完成"
}

install_docker_script() {
    echo -e "${Info} 使用官方脚本安装 Docker..."
    
    curl -fsSL https://get.docker.com | sh
    
    if command -v systemctl &>/dev/null; then
        systemctl enable docker
        systemctl start docker
    fi
    
    echo -e "${Info} Docker 安装完成"
}

# ==================== FreeBSD 安装 ====================
install_docker_freebsd() {
    echo -e "${Info} 开始安装 Docker (FreeBSD)..."
    echo -e "${Warning} 注意: FreeBSD 原生不支持 Docker"
    echo -e "${Info} 可选方案:"
    echo -e " 1. 使用 Podman (推荐)"
    echo -e " 2. 使用 bhyve 虚拟机运行 Linux + Docker"
    echo -e " 3. 使用 jail (FreeBSD 原生容器)"
    
    read -p "选择安装方式 [1-3]: " choice
    
    case "$choice" in
        1)
            install_podman_freebsd
            ;;
        2)
            echo -e "${Warning} 请使用 vm-bhyve 创建 Linux 虚拟机"
            pkg install -y vm-bhyve
            ;;
        3)
            echo -e "${Info} jail 是 FreeBSD 内置功能，无需安装"
            echo -e "${Tip} 使用 ezjail 或 iocage 简化 jail 管理"
            read -p "是否安装 iocage? [y/N]: " install_iocage
            [[ $install_iocage =~ ^[Yy]$ ]] && pkg install -y py39-iocage
            ;;
        *)
            echo -e "${Error} 无效选择"
            ;;
    esac
}

install_podman_freebsd() {
    echo -e "${Info} 安装 Podman (FreeBSD)..."
    
    pkg update
    pkg install -y podman buildah skopeo
    
    # 配置 Podman
    echo -e "${Info} 配置 Podman..."
    
    # 创建必要目录
    mkdir -p /var/lib/containers/storage
    mkdir -p ~/.config/containers
    
    # 创建 registries.conf
    cat > ~/.config/containers/registries.conf << 'EOF'
[registries.search]
registries = ['docker.io', 'quay.io', 'ghcr.io']

[registries.insecure]
registries = []

[registries.block]
registries = []
EOF

    echo -e "${Info} Podman 安装完成"
    echo -e "${Tip} 使用 'podman' 替代 'docker' 命令"
    echo -e "${Tip} 示例: podman run hello-world"
}

# ==================== 安装 Docker Compose ====================
install_docker_compose() {
    echo -e "${Info} 安装 Docker Compose..."
    
    # 检测架构
    local arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        armv7l) arch="armv7" ;;
        *) echo -e "${Error} 不支持的架构: $arch"; return 1 ;;
    esac
    
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    # 下载
    local url="https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-${os}-${arch}"
    
    curl -sL "$url" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    if [ -f /usr/local/bin/docker-compose ]; then
        echo -e "${Info} Docker Compose 安装完成"
        docker-compose --version
    else
        echo -e "${Error} 安装失败"
    fi
}

# ==================== 卸载 Docker ====================
uninstall_docker() {
    echo -e "${Warning} 确定要卸载 Docker? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    case "$OS_DISTRO" in
        debian|ubuntu)
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            apt-get autoremove -y
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        centos|rhel|rocky|alma|fedora)
            yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        alpine)
            apk del docker docker-cli-compose
            ;;
        freebsd)
            pkg remove -y podman buildah skopeo
            ;;
    esac
    
    rm -f /usr/local/bin/docker-compose
    
    echo -e "${Info} Docker 已卸载"
}

# ==================== Docker 管理 ====================
docker_status() {
    echo -e "${Info} Docker 服务状态:"
    
    if command -v systemctl &>/dev/null; then
        systemctl status docker --no-pager 2>/dev/null || echo "systemd 服务不可用"
    elif command -v service &>/dev/null; then
        service docker status
    fi
    
    echo -e ""
    echo -e "${Info} 容器列表:"
    docker ps -a 2>/dev/null || echo "Docker 未运行"
    
    echo -e ""
    echo -e "${Info} 镜像列表:"
    docker images 2>/dev/null || echo "Docker 未运行"
}

docker_start() {
    echo -e "${Info} 启动 Docker..."
    if command -v systemctl &>/dev/null; then
        systemctl start docker
    elif command -v service &>/dev/null; then
        service docker start
    fi
}

docker_stop() {
    echo -e "${Info} 停止 Docker..."
    if command -v systemctl &>/dev/null; then
        systemctl stop docker
    elif command -v service &>/dev/null; then
        service docker stop
    fi
}

# ==================== 配置镜像加速 ====================
config_mirror() {
    echo -e "${Info} 配置 Docker 镜像加速..."
    
    echo -e " ${Green}1.${Reset} 阿里云 (需要登录获取专属地址)"
    echo -e " ${Green}2.${Reset} 腾讯云"
    echo -e " ${Green}3.${Reset} 华为云"
    echo -e " ${Green}4.${Reset} 中科大"
    echo -e " ${Green}5.${Reset} 网易云"
    echo -e " ${Green}6.${Reset} 自定义"
    
    read -p "请选择 [1-6]: " mirror_choice
    
    local mirror_url=""
    case "$mirror_choice" in
        1)
            echo -e "${Tip} 请访问 https://cr.console.aliyun.com/cn-hangzhou/instances/mirrors 获取加速地址"
            read -p "输入您的阿里云加速地址: " mirror_url
            ;;
        2)
            mirror_url="https://mirror.ccs.tencentyun.com"
            ;;
        3)
            mirror_url="https://05f073ad3c0010ea0f4bc00b7105ec20.mirror.swr.myhuaweicloud.com"
            ;;
        4)
            mirror_url="https://docker.mirrors.ustc.edu.cn"
            ;;
        5)
            mirror_url="https://hub-mirror.c.163.com"
            ;;
        6)
            read -p "输入自定义镜像地址: " mirror_url
            ;;
    esac
    
    if [ -n "$mirror_url" ]; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
    "registry-mirrors": ["$mirror_url"]
}
EOF
        
        echo -e "${Info} 镜像加速配置完成，重启 Docker 生效"
        docker_stop
        sleep 2
        docker_start
    fi
}

# ==================== 主菜单 ====================
show_docker_menu() {
    # Serv00/HostUno 环境检测
    local is_serv00=false
    hostname 2>/dev/null | grep -qiE "serv00|hostuno" && is_serv00=true
    command -v devil &>/dev/null && is_serv00=true
    
    if [ "$is_serv00" = true ]; then
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔╦╗╔═╗╔═╗╦╔═╔═╗╦═╗
     ║║║ ║║  ╠╩╗║╣ ╠╦╝
    ═╩╝╚═╝╚═╝╩ ╩╚═╝╩╚═
EOF
        echo -e "${Reset}"
        echo -e "${Red}========================================${Reset}"
        echo -e "${Error} Serv00/HostUno 环境不支持 Docker"
        echo -e "${Red}========================================${Reset}"
        echo -e ""
        echo -e " 原因: Docker 需要 root 权限和内核支持"
        echo -e "       Serv00 是 FreeBSD 共享主机，无法安装容器运行时"
        echo -e ""
        echo -e "${Tip} 替代方案:"
        echo -e "  ${Green}1.${Reset} 直接运行应用二进制文件 (不使用容器)"
        echo -e "  ${Green}2.${Reset} 使用其他支持 Docker 的 VPS"
        echo -e ""
        read -p "按回车返回主菜单..."
        return 0
    fi
    
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔╦╗╔═╗╔═╗╦╔═╔═╗╦═╗
     ║║║ ║║  ╠╩╗║╣ ╠╦╝
    ═╩╝╚═╝╚═╝╩ ╩╚═╝╩╚═
    Docker 管理
EOF
        echo -e "${Reset}"
        
        # 显示状态
        check_docker
        check_docker_compose
        echo -e ""
        
        echo -e "${Green}==================== Docker 管理 ====================${Reset}"
        echo -e " ${Yellow}安装${Reset}"
        echo -e " ${Green}1.${Reset}  一键安装 Docker"
        echo -e " ${Green}2.${Reset}  安装 Docker Compose"
        echo -e " ${Green}3.${Reset}  卸载 Docker"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}服务${Reset}"
        echo -e " ${Green}4.${Reset}  启动 Docker"
        echo -e " ${Green}5.${Reset}  停止 Docker"
        echo -e " ${Green}6.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}配置${Reset}"
        echo -e " ${Green}7.${Reset}  配置镜像加速"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-7]: " choice
        
        case "$choice" in
            1)
                if [ "$OS_TYPE" = "freebsd" ]; then
                    install_docker_freebsd
                else
                    install_docker_linux
                fi
                ;;
            2) install_docker_compose ;;
            3) uninstall_docker ;;
            4) docker_start ;;
            5) docker_stop ;;
            6) docker_status ;;
            7) config_mirror ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 主程序 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    [ -z "$ENV_TYPE" ] && detect_environment 2>/dev/null
    show_docker_menu
fi
