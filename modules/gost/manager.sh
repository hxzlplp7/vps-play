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
    metadata:
      keepAlive: true
      ttl: 10s
      readBufferSize: 4096
  forwarder:
    nodes:
    - name: target-$local_port
      addr: $target_addr
EOF

    echo -e "${Info} 配置已添加"
    echo -e "${Tip} 请重启服务以生效: [5] 重启服务"
}

# 快速中转 (粘贴节点链接批量配置)
quick_forward() {
    if ! check_gost_installed; then
        echo -e "${Error} GOST 未安装，请先安装"
        return
    fi
    
    echo -e ""
    echo -e "${Cyan}========== 快速中转配置 ==========${Reset}"
    echo -e "${Tip} 粘贴落地机节点链接，自动解析并配置转发"
    echo -e ""
    echo -e "${Info} 支持的节点格式:"
    echo -e "  - vmess://..."
    echo -e "  - vless://..."
    echo -e "  - trojan://..."
    echo -e "  - hysteria2://..."
    echo -e "  - hy2://..."
    echo -e "  - tuic://..."
    echo -e "  - ss://..."
    echo -e ""
    echo -e "${Yellow}请粘贴节点链接 (一行一个，输入空行结束):${Reset}"
    echo -e ""
    
    local nodes=()
    while true; do
        read -r line
        if [ -z "$line" ]; then
            break
        fi
        nodes+=("$line")
    done
    
    if [ ${#nodes[@]} -eq 0 ]; then
        echo -e "${Error} 未输入任何节点"
        return
    fi
    
    echo -e ""
    echo -e "${Info} 解析到 ${#nodes[@]} 个节点"
    echo -e ""
    
    # 解析节点获取 IP 和端口
    local configs=()
    local index=1
    
    for node in "${nodes[@]}"; do
        local node_ip=""
        local node_port=""
        local node_type=""
        
        # 解析不同类型的节点
        if [[ "$node" == vmess://* ]]; then
            node_type="vmess"
            # vmess 是 base64 编码的 JSON
            local decoded=$(echo "${node#vmess://}" | base64 -d 2>/dev/null)
            if [ -n "$decoded" ]; then
                node_ip=$(echo "$decoded" | grep -oP '"add"\s*:\s*"\K[^"]+' | head -1)
                node_port=$(echo "$decoded" | grep -oP '"port"\s*:\s*"?\K[0-9]+' | head -1)
            fi
        elif [[ "$node" == vless://* ]]; then
            node_type="vless"
            # vless://uuid@server:port?params#name
            local server_part=$(echo "${node#vless://}" | cut -d'#' -f1 | cut -d'?' -f1)
            node_ip=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f1)
            node_port=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f2)
        elif [[ "$node" == trojan://* ]]; then
            node_type="trojan"
            # trojan://password@server:port?params#name
            local server_part=$(echo "${node#trojan://}" | cut -d'#' -f1 | cut -d'?' -f1)
            node_ip=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f1)
            node_port=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f2)
        elif [[ "$node" == hysteria2://* ]] || [[ "$node" == hy2://* ]]; then
            node_type="hy2"
            # hysteria2://auth@server:port?params#name
            local clean_node="${node#hysteria2://}"
            clean_node="${clean_node#hy2://}"
            local server_part=$(echo "$clean_node" | cut -d'#' -f1 | cut -d'?' -f1)
            node_ip=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f1)
            node_port=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f2)
        elif [[ "$node" == tuic://* ]]; then
            node_type="tuic"
            # tuic://uuid:password@server:port?params#name
            local server_part=$(echo "${node#tuic://}" | cut -d'#' -f1 | cut -d'?' -f1)
            node_ip=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f1)
            node_port=$(echo "$server_part" | sed 's/.*@//' | cut -d':' -f2)
        elif [[ "$node" == ss://* ]]; then
            node_type="ss"
            # ss://base64@server:port#name 或 ss://base64#name
            local clean_node="${node#ss://}"
            if [[ "$clean_node" == *@* ]]; then
                local server_part=$(echo "$clean_node" | cut -d'#' -f1 | sed 's/.*@//')
                node_ip=$(echo "$server_part" | cut -d':' -f1)
                node_port=$(echo "$server_part" | cut -d':' -f2)
            else
                # 纯base64格式，尝试解码
                local decoded=$(echo "$clean_node" | cut -d'#' -f1 | base64 -d 2>/dev/null)
                if [ -n "$decoded" ]; then
                    node_ip=$(echo "$decoded" | sed 's/.*@//' | cut -d':' -f1)
                    node_port=$(echo "$decoded" | sed 's/.*@//' | cut -d':' -f2)
                fi
            fi
        else
            echo -e "${Warning} 节点 $index: 无法识别的格式，跳过"
            ((index++))
            continue
        fi
        
        # 检查解析结果
        if [ -z "$node_ip" ] || [ -z "$node_port" ]; then
            echo -e "${Warning} 节点 $index: 解析失败，跳过"
            ((index++))
            continue
        fi
        
        # 获取节点名称
        local node_name=$(echo "$node" | grep -oP '#\K.*' | head -1)
        [ -z "$node_name" ] && node_name="节点$index"
        
        echo -e "${Cyan}[$index] ${node_type} - ${node_name}${Reset}"
        echo -e "    落地: ${node_ip}:${node_port}"
        
        # 询问本地监听端口
        read -p "    本地端口 [默认 $node_port]: " local_port
        local_port=${local_port:-$node_port}
        
        # 保存配置: 本地端口|目标IP|目标端口|名称|原始节点
        configs+=("$local_port|$node_ip|$node_port|$node_name|$node")
        echo -e "    ${Green}✓${Reset} 配置: 本地 $local_port -> ${node_ip}:${node_port}"
        echo -e ""
        
        ((index++))
    done
    
    if [ ${#configs[@]} -eq 0 ]; then
        echo -e "${Error} 没有有效的配置"
        return
    fi
    
    echo -e ""
    echo -e "${Info} 共配置 ${#configs[@]} 条转发规则"
    read -p "确认写入配置? [Y/n]: " confirm
    [[ $confirm =~ ^[Nn]$ ]] && return
    
    # 获取中转机IP
    local relay_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s4 ifconfig.me 2>/dev/null || curl -s4 api.ipify.org 2>/dev/null)
    if [ -z "$relay_ip" ]; then
        read -p "无法获取中转机IP，请手动输入: " relay_ip
    fi
    
    # 清空旧配置并写入新配置
    echo "services:" > "$GOST_CONF"
    
    # 存储中转后的节点
    local new_nodes=()
    
    for cfg in "${configs[@]}"; do
        local local_port=$(echo "$cfg" | cut -d'|' -f1)
        local target_ip=$(echo "$cfg" | cut -d'|' -f2)
        local target_port=$(echo "$cfg" | cut -d'|' -f3)
        local name=$(echo "$cfg" | cut -d'|' -f4)
        local original_node=$(echo "$cfg" | cut -d'|' -f5-)
        
        # 开放端口
        open_port "$local_port" "tcp" 2>/dev/null
        open_port "$local_port" "udp" 2>/dev/null
        
        # TCP 转发
        cat >> "$GOST_CONF" <<EOF
- name: tcp-${local_port}-${name}
  addr: :${local_port}
  handler:
    type: tcp
  listener:
    type: tcp
  forwarder:
    nodes:
    - name: target-${local_port}
      addr: ${target_ip}:${target_port}
EOF
        
        # UDP 转发 (需要添加metadata配置)
        cat >> "$GOST_CONF" <<EOF
- name: udp-${local_port}-${name}
  addr: :${local_port}
  handler:
    type: udp
  listener:
    type: udp
    metadata:
      keepAlive: true
      ttl: 10s
      readBufferSize: 4096
  forwarder:
    nodes:
    - name: target-${local_port}
      addr: ${target_ip}:${target_port}
EOF
        
        # 生成中转后的节点 (替换IP和端口)
        local new_node="$original_node"
        # 替换 IP:PORT 为中转机IP:本地端口
        new_node=$(echo "$new_node" | sed "s/${target_ip}:${target_port}/${relay_ip}:${local_port}/g")
        # 处理可能只有IP的情况
        new_node=$(echo "$new_node" | sed "s/@${target_ip}:/@${relay_ip}:/g")
        
        # 修改节点名称添加中转标识
        if [[ "$new_node" == *"#"* ]]; then
            new_node=$(echo "$new_node" | sed "s/#.*/&[中转]/")
        else
            new_node="${new_node}#${name}[中转]"
        fi
        
        new_nodes+=("$new_node")
    done
    
    echo -e ""
    echo -e "${Info} 配置完成"
    
    # 自动重启
    read -p "是否立即启动/重启 GOST? [Y/n]: " auto_restart
    if [[ ! $auto_restart =~ ^[Nn]$ ]]; then
        restart_gost
    fi
    
    # 输出中转后的节点
    echo -e ""
    echo -e "${Cyan}==================== 中转后的节点链接 ====================${Reset}"
    echo -e "${Tip} 中转机 IP: ${Yellow}${relay_ip}${Reset}"
    echo -e ""
    
    for new_node in "${new_nodes[@]}"; do
        echo -e "${Green}${new_node}${Reset}"
        echo -e ""
    done
    
    # 保存到文件
    local save_file="$GOST_DIR/relay_nodes.txt"
    printf '%s\n' "${new_nodes[@]}" > "$save_file"
    echo -e "${Cyan}======================================================${Reset}"
    echo -e ""
    echo -e "${Info} 中转节点已保存到: ${Cyan}${save_file}${Reset}"
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
        echo "services:" > "$GOST_CONF"
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
        echo -e "${Yellow}7.${Reset} ${Yellow}快速中转${Reset} ${Cyan}(推荐)${Reset}"
        echo -e "${Green}8.${Reset} 添加单条转发"
        echo -e "${Green}9.${Reset} 查看配置"
        echo -e "${Green}10.${Reset} 清空配置"
        echo -e "${Green}--------------------${Reset}"
        echo -e "${Green}0.${Reset} 返回主菜单"
        echo -e ""
        
        read -p " 请选择 [0-10]: " choice
        
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
            7) quick_forward ;;
            8) add_forward ;;
            9) view_config ;;
            10) clear_config ;;
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
