#!/bin/bash
# GOST 模块 - VPS-play
# GOST v3 流量中转管理

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/gost"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

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

# ==================== 配置 ====================
GOST_DIR="$HOME/.vps-play/gost"
GOST_BIN="$GOST_DIR/gost"
GOST_CONF="$GOST_DIR/config.yaml"
GOST_LOG="$GOST_DIR/gost.log"
GOST_VERSION="3.0.0-rc10" # 固定版本，较稳定

mkdir -p "$GOST_DIR"

# ==================== 辅助函数 ====================
check_gost_installed() {
    if [ -f "$GOST_BIN" ]; then
        return 0
    else
        return 1
    fi
}

check_process_running() {
    local name=$1
    pgrep -f "$name" >/dev/null 2>&1
}

check_disk_space() {
    local available_kb=$(df -k "$GOST_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_kb" -lt 51200 ]; then # 需 50MB
        echo -e "${Error} 磁盘空间不足 (剩余 $(($available_kb/1024)) MB)"
        return 1
    fi
    return 0
}

# ==================== 安装卸载 ====================
install_gost() {
    echo -e "${Info} 开始安装 GOST v3..."
    
    if ! check_disk_space; then
        return 1
    fi

    local arch="amd64"
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7*) arch="armv7" ;;
        *) echo -e "${Error} 不支持的架构: $(uname -m)"; return 1 ;;
    esac

    local os="linux"
    if [ "$(uname)" == "FreeBSD" ]; then
        os="freebsd"
    fi

    # 使用 GitHub Release
    local filename="gost_${GOST_VERSION}_${os}_${arch}.tar.gz"
    local url="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/${filename}"
    
    echo -e "${Info} 下载地址: $url"
    
    cd "$GOST_DIR"
    if curl -L -o "gost.tar.gz" "$url"; then
        echo -e "${Info} 下载成功，正在解压..."
        tar -xzf "gost.tar.gz"
        rm "gost.tar.gz"
        chmod +x gost
        
        if check_gost_installed; then
            echo -e "${Info} GOST 安装成功"
            # 初始化配置
            if [ ! -f "$GOST_CONF" ]; then
                echo "services: []" > "$GOST_CONF"
            fi
        else
             echo -e "${Error} 安装失败: 二进制文件未找到"
        fi
    else
        echo -e "${Error} 下载失败，请检查网络"
        return 1
    fi
}

uninstall_gost() {
    echo -e "${Info} 正在卸载 GOST..."
    stop_gost 2>/dev/null
    rm -rf "$GOST_DIR"
    echo -e "${Info} 卸载完成"
}

# ==================== 服务管理 ====================
start_gost() {
    if ! check_gost_installed; then
        echo -e "${Error} GOST 未安装"
        return 1
    fi
    
    echo -e "${Info} 启动 GOST..."
    start_process "gost" "$GOST_BIN -C $GOST_CONF" "$GOST_DIR"
    
    sleep 1
    if check_process_running "gost"; then
        echo -e "${Info} GOST 启动成功"
    else
        echo -e "${Error} GOST 启动失败，请检查日志"
    fi
}

stop_gost() {
    echo -e "${Info} 停止 GOST..."
    stop_process "gost"
}

restart_gost() {
    stop_gost
    sleep 1
    start_gost
}

# ==================== 配置管理 ====================
add_forward() {
    if ! check_gost_installed; then
        echo -e "${Error} GOST 未安装"
        return
    fi

    echo -e "${Info} 添加端口转发 (TCP+UDP)"
    echo -e "${Tip} 将本地端口流量转发到远程目标"
    
    read -p "本地监听端口: " local_port
    read -p "目标地址 (如 1.1.1.1:80): " target_addr
    
    if [ -z "$local_port" ] || [ -z "$target_addr" ]; then
        echo -e "${Error} 输入不能为空"
        return
    fi
    
    # 开放端口
    open_port "$local_port" "tcp"
    open_port "$local_port" "udp"

    # 追加 YAML 配置
    # 注意：这里使用简单的追加方式，对于复杂 YAML 来说是不规范的，
    # 但对于 gost 的 services 列表结构是有效的
    
    cat >> "$GOST_CONF" <<EOF
- name: forward-$local_port
  addr: :$local_port
  handler:
    type: tcp
  listener:
    type: tcp
  forwarder:
    nodes:
    - name: target-$local_port
      addr: $target_addr
- name: forward-$local_port-udp
  addr: :$local_port
  handler:
    type: udp
  listener:
    type: udp
  forwarder:
    nodes:
    - name: target-$local_port
      addr: $target_addr
EOF

    echo -e "${Info} 配置已添加"
    echo -e "${Tip} 请重启服务以生效: [5] 重启服务"
}

view_config() {
    if [ -f "$GOST_CONF" ]; then
        echo -e "${Green}配置文件内容 ($GOST_CONF):${Reset}"
        cat "$GOST_CONF"
    else
        echo -e "${Warning} 配置文件不存在"
    fi
}

clear_config() {
    read -p "确定清空所有配置吗? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        echo "services: []" > "$GOST_CONF"
        echo -e "${Info} 配置已清空，请重启服务"
    fi
}

# ==================== 菜单 ====================
show_gost_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╔═╗╔═╗╔╦╗  ╦  ╦╔═╗
    ║ ╦║ ║╚═╗ ║   ╚╗╔╝╚═╗
    ╚═╝╚═╝╚═╝ ╩    ╚╝  ╩ 
    流量中转工具 (GOST v3)
EOF
        echo -e "${Reset}"
        
        local status_text="${Red}已停止${Reset}"
        if check_process_running "gost"; then
            status_text="${Green}运行中${Reset}"
        fi
        
        echo -e "  状态: $status_text | 版本: ${GOST_VERSION}"
        echo -e ""
        echo -e "${Green}1.${Reset} 安装 GOST"
        echo -e "${Green}2.${Reset} 卸载 GOST"
        echo -e "${Green}--------------------${Reset}"
        echo -e "${Green}3.${Reset} 启动服务"
        echo -e "${Green}4.${Reset} 停止服务"
        echo -e "${Green}5.${Reset} 重启服务"
        echo -e "${Green}6.${Reset} 查看日志"
        echo -e "${Green}--------------------${Reset}"
        echo -e "${Green}7.${Reset} 添加转发 (Port -> IP:Port)"
        echo -e "${Green}8.${Reset} 查看配置"
        echo -e "${Green}9.${Reset} 清空配置"
        echo -e "${Green}--------------------${Reset}"
        echo -e "${Green}0.${Reset} 返回主菜单"
        echo -e ""
        
        read -p " 请选择 [0-9]: " choice
        
        case "$choice" in
            1) install_gost ;;
            2) uninstall_gost ;;
            3) start_gost ;;
            4) stop_gost ;;
            5) restart_gost ;;
            6) 
                if [ -f "$GOST_LOG" ]; then
                    echo -e "${Info} 最近 20 行日志:"
                    tail -n 20 "$GOST_LOG"
                else
                    echo -e "${Warning} 暂无日志"
                fi
                ;;
            7) add_forward ;;
            8) view_config ;;
            9) clear_config ;;
            0) return 0 ;;
            *) echo -e "${Error} 无效选择" ;;
        esac
        
        echo -e ""
        read -p "按回车继续..."
    done
}

# ==================== 入口 ====================
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_gost_menu
fi
