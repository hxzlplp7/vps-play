#!/bin/bash
# VPS-play 系统清理工具
# 功能: 清理包管理器缓存、日志、Docker垃圾等

# 颜色定义
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"
Info="${Green}[信息]${Reset}"
Error="${Red}[错误]${Reset}"
Warning="${Yellow}[警告]${Reset}"

# 磁盘使用情况
show_disk_usage() {
    echo -e "${Info} 当前磁盘使用情况:"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print "  " $5 " " $6 }'
}

clean_system() {
    clear
    echo -e "${Cyan}==================== 系统清理 ====================${Reset}"
    show_disk_usage
    echo -e "${Cyan}-------------------------------------------------${Reset}"
    
    echo -e "${Info} 正在清理包管理器缓存..."
    if command -v apt-get &>/dev/null; then
        apt-get clean
        apt-get autoremove -y
        rm -rf /var/lib/apt/lists/*
        echo -e "  ✓ APT 缓存已清理"
    elif command -v yum &>/dev/null; then
        yum clean all
        yum autoremove -y 2>/dev/null
        echo -e "  ✓ YUM 缓存已清理"
    elif command -v apk &>/dev/null; then
        apk cache clean
        echo -e "  ✓ APK 缓存已清理"
    fi
    
    echo -e "${Info} 正在清理系统日志..."
    # 清理 journald 日志
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=1d 2>/dev/null
        journalctl --vacuum-size=50M 2>/dev/null
        echo -e "  ✓ Journal 日志已清理"
    fi
    
    # 清理 /var/log 下的旧日志
    find /var/log -type f -name "*.gz" -delete
    find /var/log -type f -name "*.log.[0-9]" -delete
    # 清空大日志文件但不删除
    for log in $(find /var/log -type f -name "*.log" -size +50M); do
        > "$log"
    done
    echo -e "  ✓ 旧日志文件已清理"
    
    echo -e "${Info} 正在清理临时文件..."
    rm -rf /tmp/*
    echo -e "  ✓ /tmp 已清理"
    
    # 清理 Docker (如果存在)
    if command -v docker &>/dev/null; then
        echo -e "${Info} 正在清理 Docker 垃圾 (未使用镜像、容器、卷)..."
        docker system prune -a -f --volumes
        echo -e "  ✓ Docker 已清理"
    fi
    
    echo -e "${Cyan}-------------------------------------------------${Reset}"
    echo -e "${Green}清理完成!${Reset}"
    show_disk_usage
    echo -e "${Cyan}=================================================${Reset}"
    
    read -p "按回车继续..."
}

# 导出函数
export -f clean_system
