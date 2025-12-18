#!/bin/bash
# 保活系统 - VPS-play
# 本地进程保活 + 远程 SSH 复活 + Cron 任务

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPSPLAY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载工具库
source "$VPSPLAY_DIR/utils/env_detect.sh" 2>/dev/null
source "$VPSPLAY_DIR/utils/process_manager.sh" 2>/dev/null

# ==================== 配置 ====================
KEEPALIVE_DIR="$HOME/.vps-play/keepalive"
KEEPALIVE_LOG="$KEEPALIVE_DIR/keepalive.log"
CRON_MARKER="# VPS-play keepalive"

mkdir -p "$KEEPALIVE_DIR"

# ==================== 日志函数 ====================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$KEEPALIVE_LOG"
    echo -e "$msg"
}

# ==================== 进程保活检测 ====================
# 检查进程是否运行
check_process_alive() {
    local name=$1
    local pid_file="$HOME/.vps-play/processes/${name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0  # 运行中
        fi
    fi
    return 1  # 未运行
}

# 重启进程
revive_process() {
    local name=$1
    local info_file="$HOME/.vps-play/processes/${name}.info"
    
    if [ -f "$info_file" ]; then
        source "$info_file"
        log "正在重启进程: $name"
        
        cd "$working_dir" 2>/dev/null || cd "$HOME"
        nohup bash -c "$command" > "$HOME/.vps-play/processes/${name}.log" 2>&1 &
        echo $! > "$HOME/.vps-play/processes/${name}.pid"
        
        sleep 2
        if check_process_alive "$name"; then
            log "进程 $name 重启成功"
            return 0
        else
            log "进程 $name 重启失败"
            return 1
        fi
    else
        log "进程 $name 信息文件不存在"
        return 1
    fi
}

# ==================== 保活服务列表 ====================
KEEPALIVE_SERVICES="$KEEPALIVE_DIR/services.list"

# 添加服务到保活列表
add_keepalive_service() {
    local name=$1
    
    if ! grep -q "^${name}$" "$KEEPALIVE_SERVICES" 2>/dev/null; then
        echo "$name" >> "$KEEPALIVE_SERVICES"
        log "已添加服务到保活列表: $name"
    else
        log "服务已在保活列表中: $name"
    fi
}

# 从保活列表移除服务
remove_keepalive_service() {
    local name=$1
    
    if [ -f "$KEEPALIVE_SERVICES" ]; then
        grep -v "^${name}$" "$KEEPALIVE_SERVICES" > "${KEEPALIVE_SERVICES}.tmp"
        mv "${KEEPALIVE_SERVICES}.tmp" "$KEEPALIVE_SERVICES"
        log "已从保活列表移除: $name"
    fi
}

# 列出保活服务
list_keepalive_services() {
    echo -e "${Info} 保活服务列表:"
    if [ -f "$KEEPALIVE_SERVICES" ] && [ -s "$KEEPALIVE_SERVICES" ]; then
        local i=1
        while read name; do
            if check_process_alive "$name"; then
                echo -e "  [$i] $name - ${Green}运行中${Reset}"
            else
                echo -e "  [$i] $name - ${Red}已停止${Reset}"
            fi
            i=$((i + 1))
        done < "$KEEPALIVE_SERVICES"
    else
        echo -e "  (空)"
    fi
}

# ==================== 保活检查任务 ====================
# 执行一次保活检查
run_keepalive_check() {
    log "========== 保活检查开始 =========="
    
    if [ ! -f "$KEEPALIVE_SERVICES" ] || [ ! -s "$KEEPALIVE_SERVICES" ]; then
        log "保活列表为空"
        return 0
    fi
    
    local revived=0
    local failed=0
    
    while read name; do
        [ -z "$name" ] && continue
        
        if check_process_alive "$name"; then
            log "✓ $name 运行正常"
        else
            log "✗ $name 已停止，尝试重启..."
            if revive_process "$name"; then
                revived=$((revived + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done < "$KEEPALIVE_SERVICES"
    
    log "保活检查完成: 已重启 $revived 个，失败 $failed 个"
    log "========== 保活检查结束 =========="
}

# ==================== Cron 任务管理 ====================
# 创建保活脚本
create_keepalive_script() {
    local script_file="$KEEPALIVE_DIR/check.sh"
    
    cat > "$script_file" << 'SCRIPT_EOF'
#!/bin/bash
# VPS-play 保活检查脚本

KEEPALIVE_DIR="$HOME/.vps-play/keepalive"
KEEPALIVE_LOG="$KEEPALIVE_DIR/keepalive.log"
KEEPALIVE_SERVICES="$KEEPALIVE_DIR/services.list"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$KEEPALIVE_LOG"
}

check_process_alive() {
    local name=$1
    local pid_file="$HOME/.vps-play/processes/${name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

revive_process() {
    local name=$1
    local info_file="$HOME/.vps-play/processes/${name}.info"
    
    if [ -f "$info_file" ]; then
        source "$info_file"
        cd "$working_dir" 2>/dev/null || cd "$HOME"
        nohup bash -c "$command" > "$HOME/.vps-play/processes/${name}.log" 2>&1 &
        echo $! > "$HOME/.vps-play/processes/${name}.pid"
        return 0
    fi
    return 1
}

# 主逻辑
log "保活检查开始"

if [ -f "$KEEPALIVE_SERVICES" ]; then
    while read name; do
        [ -z "$name" ] && continue
        if ! check_process_alive "$name"; then
            log "$name 已停止，尝试重启"
            revive_process "$name"
        fi
    done < "$KEEPALIVE_SERVICES"
fi

log "保活检查完成"
SCRIPT_EOF

    chmod +x "$script_file"
    echo -e "${Info} 保活脚本已创建: $script_file"
}

# 添加 Cron 任务
add_cron_job() {
    local interval=${1:-5}  # 默认 5 分钟
    local script_file="$KEEPALIVE_DIR/check.sh"
    
    # 创建脚本
    create_keepalive_script
    
    # 获取当前 crontab
    local crontab_content=$(crontab -l 2>/dev/null | grep -v "$CRON_MARKER")
    
    # 添加新任务
    local new_job="*/$interval * * * * $script_file $CRON_MARKER"
    
    echo "$crontab_content" | { cat; echo "$new_job"; } | crontab -
    
    echo -e "${Info} Cron 任务已添加 (每 $interval 分钟检查一次)"
}

# 移除 Cron 任务
remove_cron_job() {
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -
    echo -e "${Info} Cron 任务已移除"
}

# 查看 Cron 任务
show_cron_job() {
    echo -e "${Info} 当前 Cron 任务:"
    crontab -l 2>/dev/null | grep "$CRON_MARKER" || echo "  (无)"
}

# ==================== 远程 SSH 复活 ====================
# 生成远程复活脚本
generate_remote_script() {
    local host=$1
    local user=$2
    local script_file="$KEEPALIVE_DIR/remote_revive_${host}.sh"
    
    cat > "$script_file" << REMOTE_EOF
#!/bin/bash
# 远程复活脚本 - $host
# 用于从其他服务器 SSH 复活此服务器上的服务

SSH_HOST="$user@$host"
REMOTE_SCRIPT="\$HOME/.vps-play/keepalive/check.sh"

echo "正在连接到 $host..."
ssh -o ConnectTimeout=10 -o BatchMode=yes "\$SSH_HOST" "bash \$REMOTE_SCRIPT"

if [ \$? -eq 0 ]; then
    echo "远程复活完成"
else
    echo "远程连接失败"
fi
REMOTE_EOF

    chmod +x "$script_file"
    echo -e "${Info} 远程复活脚本已生成: $script_file"
    echo -e "${Tip} 在其他服务器上运行此脚本即可复活本机服务"
}

# ==================== 心跳检测 ====================
# HTTP 心跳
http_heartbeat() {
    local url=$1
    local timeout=${2:-5}
    
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$url" | grep -q "^[23]"; then
        return 0
    fi
    return 1
}

# TCP 心跳
tcp_heartbeat() {
    local host=$1
    local port=$2
    local timeout=${3:-3}
    
    if command -v nc &>/dev/null; then
        timeout "$timeout" nc -z "$host" "$port" &>/dev/null
        return $?
    fi
    return 1
}

# ==================== 主菜单 ====================
show_keepalive_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╦╔═╔═╗╔═╗╔═╗╔═╗╦  ╦╦  ╦╔═╗
    ╠╩╗║╣ ║╣ ╠═╝╠═╣║  ║╚╗╔╝║╣ 
    ╩ ╩╚═╝╚═╝╩  ╩ ╩╩═╝╩ ╚╝ ╚═╝
    进程保活系统
EOF
        echo -e "${Reset}"
        
        echo -e "${Green}==================== 保活管理 ====================${Reset}"
        echo -e " ${Yellow}服务管理${Reset}"
        echo -e " ${Green}1.${Reset}  添加服务到保活列表"
        echo -e " ${Green}2.${Reset}  从保活列表移除服务"
        echo -e " ${Green}3.${Reset}  查看保活列表"
        echo -e " ${Green}4.${Reset}  立即执行保活检查"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}Cron 任务${Reset}"
        echo -e " ${Green}5.${Reset}  添加定时保活任务"
        echo -e " ${Green}6.${Reset}  移除定时保活任务"
        echo -e " ${Green}7.${Reset}  查看定时任务"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}远程复活${Reset}"
        echo -e " ${Green}8.${Reset}  生成远程复活脚本"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}9.${Reset}  查看保活日志"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}=================================================${Reset}"
        
        read -p " 请选择 [0-9]: " choice
        
        case "$choice" in
            1)
                echo -e ""
                echo -e "${Info} 可用的服务:"
                list_processes 2>/dev/null || echo "  (无)"
                echo -e ""
                read -p "输入要添加的服务名称: " service_name
                [ -n "$service_name" ] && add_keepalive_service "$service_name"
                ;;
            2)
                echo -e ""
                list_keepalive_services
                echo -e ""
                read -p "输入要移除的服务名称: " service_name
                [ -n "$service_name" ] && remove_keepalive_service "$service_name"
                ;;
            3)
                echo -e ""
                list_keepalive_services
                ;;
            4)
                echo -e ""
                run_keepalive_check
                ;;
            5)
                echo -e ""
                read -p "检查间隔 (分钟) [默认 5]: " interval
                add_cron_job "${interval:-5}"
                ;;
            6)
                remove_cron_job
                ;;
            7)
                echo -e ""
                show_cron_job
                ;;
            8)
                echo -e ""
                read -p "本机 IP 或域名: " host
                read -p "SSH 用户名: " user
                generate_remote_script "$host" "${user:-$(whoami)}"
                ;;
            9)
                echo -e ""
                if [ -f "$KEEPALIVE_LOG" ]; then
                    echo -e "${Info} 保活日志 (最后 30 行):"
                    tail -30 "$KEEPALIVE_LOG"
                else
                    echo -e "${Warning} 日志文件不存在"
                fi
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
    if [ -z "$ENV_TYPE" ]; then
        detect_environment 2>/dev/null
    fi
    show_keepalive_menu
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
