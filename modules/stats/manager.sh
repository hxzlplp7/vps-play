#!/bin/bash
# VPS-play 流量统计 API 服务
# 为 sing-box/xray 提供流量统计接口

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/stats"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"

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
STATS_DIR="$HOME/.vps-play/stats"
STATS_CONF="$STATS_DIR/config.json"
STATS_DATA="$STATS_DIR/traffic.json"
STATS_LOG="$STATS_DIR/api.log"
STATS_PID="$STATS_DIR/api.pid"

mkdir -p "$STATS_DIR"

# ==================== 流量配额配置 ====================
# 默认流量配额 (字节)
DEFAULT_TOTAL=107374182400  # 100GB
TRAFFIC_TOTAL=$DEFAULT_TOTAL
TRAFFIC_EXPIRE=4102329600   # 2099-12-31

# ==================== 获取 sing-box 流量 ====================
get_singbox_traffic() {
    local api_port=$(cat "$HOME/.vps-play/singbox/api_port" 2>/dev/null)
    if [ -z "$api_port" ]; then
        echo '{"upload":0,"download":0,"total":0}'
        return
    fi
    
    # 调用 sing-box clash api 获取流量
    local response=$(curl -s "http://127.0.0.1:${api_port}/traffic" 2>/dev/null | head -1)
    
    if [ -n "$response" ]; then
        # 解析流量数据
        local up=$(echo "$response" | grep -oP '"up":\s*\K[0-9]+' | head -1)
        local down=$(echo "$response" | grep -oP '"down":\s*\K[0-9]+' | head -1)
        up=${up:-0}
        down=${down:-0}
        echo "{\"upload\":$up,\"download\":$down,\"total\":$((up+down))}"
    else
        # 从保存的文件读取
        if [ -f "$STATS_DATA" ]; then
            cat "$STATS_DATA"
        else
            echo '{"upload":0,"download":0,"total":0}'
        fi
    fi
}

# ==================== 获取 xray 流量 ====================
get_xray_traffic() {
    local api_port=$(cat "$HOME/.vps-play/argo/api_port" 2>/dev/null)
    if [ -z "$api_port" ]; then
        echo '{"upload":0,"download":0,"total":0}'
        return
    fi
    
    # 调用 xray api 获取流量 (需要配置 api 入站)
    local response=$(curl -s "http://127.0.0.1:${api_port}/stats/query" \
        -H "Content-Type: application/json" \
        -d '{"reset": false}' 2>/dev/null)
    
    if [ -n "$response" ]; then
        local up=$(echo "$response" | grep -oP '"uplink":\s*\K[0-9]+' | awk '{sum+=$1}END{print sum}')
        local down=$(echo "$response" | grep -oP '"downlink":\s*\K[0-9]+' | awk '{sum+=$1}END{print sum}')
        up=${up:-0}
        down=${down:-0}
        echo "{\"upload\":$up,\"download\":$down,\"total\":$((up+down))}"
    else
        echo '{"upload":0,"download":0,"total":0}'
    fi
}

# ==================== 获取汇总流量 ====================
get_total_traffic() {
    local singbox_traffic=$(get_singbox_traffic)
    local xray_traffic=$(get_xray_traffic)
    
    local sb_up=$(echo "$singbox_traffic" | grep -oP '"upload":\s*\K[0-9]+')
    local sb_down=$(echo "$singbox_traffic" | grep -oP '"download":\s*\K[0-9]+')
    local xr_up=$(echo "$xray_traffic" | grep -oP '"upload":\s*\K[0-9]+')
    local xr_down=$(echo "$xray_traffic" | grep -oP '"download":\s*\K[0-9]+')
    
    sb_up=${sb_up:-0}
    sb_down=${sb_down:-0}
    xr_up=${xr_up:-0}
    xr_down=${xr_down:-0}
    
    local total_up=$((sb_up + xr_up))
    local total_down=$((sb_down + xr_down))
    local total_used=$((total_up + total_down))
    
    # 读取配额配置
    if [ -f "$STATS_CONF" ]; then
        TRAFFIC_TOTAL=$(grep -oP '"total":\s*\K[0-9]+' "$STATS_CONF" || echo $DEFAULT_TOTAL)
        TRAFFIC_EXPIRE=$(grep -oP '"expire":\s*\K[0-9]+' "$STATS_CONF" || echo 4102329600)
    fi
    
    cat <<EOF
{
  "upload": $total_up,
  "download": $total_down,
  "used": $total_used,
  "total": $TRAFFIC_TOTAL,
  "remaining": $((TRAFFIC_TOTAL - total_used)),
  "expire": $TRAFFIC_EXPIRE,
  "singbox": $singbox_traffic,
  "xray": $xray_traffic,
  "time": $(date +%s)
}
EOF
}

# ==================== HTTP API 服务 ====================
start_api_server() {
    local port=$1
    
    if [ -f "$STATS_PID" ] && kill -0 $(cat "$STATS_PID") 2>/dev/null; then
        echo -e "${Warning} API 服务已在运行"
        return
    fi
    
    echo -e "${Info} 启动流量统计 API 服务..."
    echo -e " 端口: ${Cyan}$port${Reset}"
    
    # 使用 nc 或 socat 创建简单的 HTTP 服务
    if command -v socat &>/dev/null; then
        start_socat_server "$port" &
    elif command -v nc &>/dev/null; then
        start_nc_server "$port" &
    else
        echo -e "${Error} 需要 socat 或 nc (netcat) 来运行 API 服务"
        return 1
    fi
    
    local pid=$!
    echo $pid > "$STATS_PID"
    echo "$port" > "$STATS_DIR/api_port"
    
    sleep 1
    if kill -0 $pid 2>/dev/null; then
        echo -e "${Info} API 服务已启动 (PID: $pid)"
        echo -e "${Tip} API 地址: http://$(curl -s4 ip.sb 2>/dev/null || echo "YOUR_IP"):$port/stats"
    else
        echo -e "${Error} API 服务启动失败"
    fi
}

start_socat_server() {
    local port=$1
    while true; do
        socat TCP-LISTEN:$port,reuseaddr,fork SYSTEM:"$0 handle_request" 2>/dev/null
        sleep 1
    done
}

start_nc_server() {
    local port=$1
    while true; do
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n$(get_total_traffic)" | nc -l -p $port -q 1 2>/dev/null || \
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n$(get_total_traffic)" | nc -l $port 2>/dev/null
        sleep 0.1
    done
}

handle_request() {
    read request
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: application/json\r"
    echo -e "Access-Control-Allow-Origin: *\r"
    echo -e "\r"
    get_total_traffic
}

stop_api_server() {
    if [ -f "$STATS_PID" ]; then
        local pid=$(cat "$STATS_PID")
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            pkill -P $pid 2>/dev/null
        fi
        rm -f "$STATS_PID"
        echo -e "${Info} API 服务已停止"
    else
        echo -e "${Warning} API 服务未运行"
    fi
}

# ==================== 配置流量配额 ====================
configure_quota() {
    echo -e ""
    echo -e "${Cyan}========== 配置流量配额 ==========${Reset}"
    echo -e ""
    
    read -p "总流量 (GB) [100]: " total_gb
    total_gb=${total_gb:-100}
    TRAFFIC_TOTAL=$((total_gb * 1073741824))
    
    read -p "过期时间 (YYYY-MM-DD) [2099-12-31]: " expire_date
    expire_date=${expire_date:-2099-12-31}
    TRAFFIC_EXPIRE=$(date -d "$expire_date" +%s 2>/dev/null || echo 4102329600)
    
    # 保存配置
    cat > "$STATS_CONF" <<EOF
{
  "total": $TRAFFIC_TOTAL,
  "expire": $TRAFFIC_EXPIRE,
  "total_gb": $total_gb,
  "expire_date": "$expire_date"
}
EOF
    
    echo -e ""
    echo -e "${Info} 配置已保存"
    echo -e " 总流量: ${Cyan}${total_gb}GB${Reset}"
    echo -e " 过期时间: ${Cyan}${expire_date}${Reset}"
}

# ==================== 显示流量统计 ====================
show_traffic() {
    echo -e ""
    echo -e "${Cyan}==================== 流量统计 ====================${Reset}"
    echo -e ""
    
    local traffic=$(get_total_traffic)
    
    local upload=$(echo "$traffic" | grep -oP '"upload":\s*\K[0-9]+' | head -1)
    local download=$(echo "$traffic" | grep -oP '"download":\s*\K[0-9]+' | head -1)
    local used=$(echo "$traffic" | grep -oP '"used":\s*\K[0-9]+')
    local total=$(echo "$traffic" | grep -oP '"total":\s*\K[0-9]+' | head -1)
    local remaining=$(echo "$traffic" | grep -oP '"remaining":\s*\K-?[0-9]+')
    
    # 转换为可读格式
    format_bytes() {
        local bytes=$1
        if [ $bytes -gt 1073741824 ]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
        elif [ $bytes -gt 1048576 ]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
        elif [ $bytes -gt 1024 ]; then
            echo "$(echo "scale=2; $bytes/1024" | bc) KB"
        else
            echo "$bytes B"
        fi
    }
    
    echo -e " 上传: ${Green}$(format_bytes $upload)${Reset}"
    echo -e " 下载: ${Green}$(format_bytes $download)${Reset}"
    echo -e " 已使用: ${Yellow}$(format_bytes $used)${Reset}"
    echo -e " 总配额: ${Cyan}$(format_bytes $total)${Reset}"
    echo -e " 剩余: ${Green}$(format_bytes $remaining)${Reset}"
    
    echo -e ""
    echo -e "${Cyan}===================================================${Reset}"
}

# ==================== 菜单 ====================
show_stats_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╔╦╗╔═╗╔╦╗╔═╗
    ╚═╗ ║ ╠═╣ ║ ╚═╗
    ╚═╝ ╩ ╩ ╩ ╩ ╚═╝
    流量统计 API
EOF
        echo -e "${Reset}"
        
        local api_status="${Red}已停止${Reset}"
        if [ -f "$STATS_PID" ] && kill -0 $(cat "$STATS_PID") 2>/dev/null; then
            local api_port=$(cat "$STATS_DIR/api_port" 2>/dev/null)
            api_status="${Green}运行中${Reset} (端口: $api_port)"
        fi
        
        echo -e " API 状态: $api_status"
        echo -e ""
        
        echo -e "${Green}==================== 流量统计 ====================${Reset}"
        echo -e " ${Green}1.${Reset}  查看流量统计"
        echo -e " ${Green}2.${Reset}  配置流量配额"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}API 服务${Reset}"
        echo -e " ${Green}3.${Reset}  启动 API 服务"
        echo -e " ${Green}4.${Reset}  停止 API 服务"
        echo -e " ${Green}5.${Reset}  获取 API 地址"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}===================================================${Reset}"
        
        read -p " 请选择 [0-5]: " choice
        
        case "$choice" in
            1) show_traffic ;;
            2) configure_quota ;;
            3)
                echo -e ""
                read -p "API 端口 [随机]: " api_port
                [ -z "$api_port" ] && api_port=$(shuf -i 30000-60000 -n 1)
                start_api_server "$api_port"
                ;;
            4) stop_api_server ;;
            5)
                if [ -f "$STATS_DIR/api_port" ]; then
                    local port=$(cat "$STATS_DIR/api_port")
                    local ip=$(curl -s4 ip.sb 2>/dev/null || echo "YOUR_IP")
                    echo -e ""
                    echo -e "${Info} API 地址:"
                    echo -e " ${Cyan}http://${ip}:${port}/stats${Reset}"
                    echo -e ""
                    echo -e "${Tip} 在 worker.js 中添加此地址到 VPS_STATS_APIS 数组"
                else
                    echo -e "${Warning} API 服务未启动"
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
    case "${1:-menu}" in
        get|stats)
            get_total_traffic
            ;;
        start)
            start_api_server "${2:-$(shuf -i 30000-60000 -n 1)}"
            ;;
        stop)
            stop_api_server
            ;;
        handle_request)
            handle_request
            ;;
        menu|*)
            show_stats_menu
            ;;
    esac
fi
