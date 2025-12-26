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

# ==================== 获取 VPS 系统网络流量 ====================
# 支持 Linux 和 FreeBSD (Serv00/Hostuno)

# 检测是否为 FreeBSD
is_freebsd() {
    [ "$(uname -s)" = "FreeBSD" ] && return 0 || return 1
}

get_primary_interface() {
    local iface=""
    
    if is_freebsd; then
        # FreeBSD: 使用 netstat 获取默认路由接口
        iface=$(netstat -rn 2>/dev/null | grep "^default" | awk '{print $NF}' | head -1)
        
        # 如果没有，尝试从 ifconfig 获取第一个非 lo 接口
        if [ -z "$iface" ]; then
            iface=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -v "^lo" | head -1)
        fi
    else
        # Linux: 尝试从默认路由获取
        iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
        
        # 如果没有，尝试常见接口名
        if [ -z "$iface" ]; then
            for name in eth0 ens3 ens18 enp0s3 venet0; do
                if [ -d "/sys/class/net/$name" ]; then
                    iface="$name"
                    break
                fi
            done
        fi
        
        # 还是没有就取第一个非 lo 接口
        if [ -z "$iface" ]; then
            iface=$(ls /sys/class/net/ 2>/dev/null | grep -v lo | head -1)
        fi
    fi
    
    echo "$iface"
}

get_interface_traffic() {
    local iface=$1
    
    if [ -z "$iface" ]; then
        echo "0 0"
        return
    fi
    
    local rx_bytes=0
    local tx_bytes=0
    
    if is_freebsd; then
        # FreeBSD: 使用 netstat -ibn
        # 格式: Name Mtu Network Address Ipkts Ierrs Idrop Ibytes Opkts Oerrs Obytes Coll
        # 列:    1    2   3       4      5     6     7     8      9     10    11     12
        local stats=$(netstat -ibn 2>/dev/null | grep "^${iface}[[:space:]]" | grep "Link" | head -1)
        if [ -n "$stats" ]; then
            rx_bytes=$(echo "$stats" | awk '{print $8}')
            tx_bytes=$(echo "$stats" | awk '{print $11}')
        fi
    else
        # Linux: 从 /sys/class/net 读取
        if [ -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
            rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        # 从 /proc/net/dev 读取
        elif [ -f "/proc/net/dev" ]; then
            local line=$(grep "$iface:" /proc/net/dev 2>/dev/null)
            if [ -n "$line" ]; then
                rx_bytes=$(echo "$line" | awk '{print $2}')
                tx_bytes=$(echo "$line" | awk '{print $10}')
            fi
        fi
    fi
    
    # 确保返回数字
    rx_bytes=${rx_bytes:-0}
    tx_bytes=${tx_bytes:-0}
    
    # 验证是否为数字
    case "$rx_bytes" in
        ''|*[!0-9]*) rx_bytes=0 ;;
    esac
    case "$tx_bytes" in
        ''|*[!0-9]*) tx_bytes=0 ;;
    esac
    
    echo "$rx_bytes $tx_bytes"
}

# 检测是否为 Serv00/Hostuno 环境
is_serv00() {
    command -v devil &>/dev/null && return 0 || return 1
}

# 获取 Serv00/Hostuno 用户 IP 的流量
# 优先级: cache2/cache > web2/web > 整个服务器
get_serv00_traffic() {
    local user_ip=""
    local ip_name=""
    
    # 通过 devil vhost list 获取用户 IP
    if command -v devil &>/dev/null; then
        local vhost_list=$(devil vhost list 2>/dev/null)
        
        # 优先查找 cache2/cache
        user_ip=$(echo "$vhost_list" | grep -E "cache2?\." | awk '{print $1}' | head -1)
        if [ -n "$user_ip" ]; then
            ip_name="cache"
        fi
        
        # 如果没有 cache，查找 web2/web
        if [ -z "$user_ip" ]; then
            user_ip=$(echo "$vhost_list" | grep -E "web2?\." | awk '{print $1}' | head -1)
            if [ -n "$user_ip" ]; then
                ip_name="web"
            fi
        fi
    fi
    
    if [ -n "$user_ip" ]; then
        # 从 netstat -ibn 获取该 IP 的流量
        # 格式: ixl0 - 213.189.54.237/32 213.189.54.237 744716020 - - 170982155104 6086833 - 2891794942 -
        local stats=$(netstat -ibn 2>/dev/null | grep "$user_ip" | head -1)
        if [ -n "$stats" ]; then
            # 列: Name - Network Address Ipkts - - Ibytes Opkts - Obytes -
            # 这种格式下 Ibytes 是第8列，Obytes 是第11列
            local rx_bytes=$(echo "$stats" | awk '{print $8}')
            local tx_bytes=$(echo "$stats" | awk '{print $11}')
            
            # 验证是数字
            case "$rx_bytes" in ''|*[!0-9]*) rx_bytes=0 ;; esac
            case "$tx_bytes" in ''|*[!0-9]*) tx_bytes=0 ;; esac
            
            echo "${ip_name}(${user_ip}) $rx_bytes $tx_bytes"
            return
        fi
    fi
    
    # 回退到整个服务器流量
    local iface=$(get_primary_interface)
    local traffic=$(get_interface_traffic "$iface")
    echo "$iface(server) $(echo "$traffic" | awk '{print $1}') $(echo "$traffic" | awk '{print $2}')"
}

get_vps_traffic() {
    if is_freebsd && is_serv00; then
        # Serv00/Hostuno: 获取用户 IP 的流量
        get_serv00_traffic
    else
        # 普通 VPS: 获取主接口流量
        local iface=$(get_primary_interface)
        local traffic=$(get_interface_traffic "$iface")
        
        local rx_bytes=$(echo "$traffic" | awk '{print $1}')
        local tx_bytes=$(echo "$traffic" | awk '{print $2}')
        
        rx_bytes=${rx_bytes:-0}
        tx_bytes=${tx_bytes:-0}
        
        echo "$iface $rx_bytes $tx_bytes"
    fi
}


# JSON 解析辅助函数 (兼容 FreeBSD)
json_get_value() {
    local json="$1"
    local key="$2"
    echo "$json" | sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/' | tr -d '"'
}

# ==================== 获取汇总流量 ====================
get_total_traffic() {
    local vps_traffic=$(get_vps_traffic)
    
    local interface=$(echo "$vps_traffic" | awk '{print $1}')
    local download=$(echo "$vps_traffic" | awk '{print $2}')
    local upload=$(echo "$vps_traffic" | awk '{print $3}')
    
    download=${download:-0}
    upload=${upload:-0}
    
    local total_used=$((upload + download))
    
    # 读取配额配置 (使用兼容方式)
    if [ -f "$STATS_CONF" ]; then
        TRAFFIC_TOTAL=$(sed -n 's/.*"total"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATS_CONF" 2>/dev/null)
        TRAFFIC_EXPIRE=$(sed -n 's/.*"expire"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATS_CONF" 2>/dev/null)
        [ -z "$TRAFFIC_TOTAL" ] && TRAFFIC_TOTAL=$DEFAULT_TOTAL
        [ -z "$TRAFFIC_EXPIRE" ] && TRAFFIC_EXPIRE=4102329600
    fi
    
    cat <<EOF
{
  "upload": $upload,
  "download": $download,
  "used": $total_used,
  "total": $TRAFFIC_TOTAL,
  "remaining": $((TRAFFIC_TOTAL - total_used)),
  "expire": $TRAFFIC_EXPIRE,
  "interface": "$interface",
  "time": $(date +%s)
}
}
EOF
}



# ==================== 安装 HTTP 工具 ====================
install_http_tool() {
    echo -e "${Info} 尝试安装 HTTP 服务器工具..."
    
    # 检测包管理器并安装
    if command -v apt-get &>/dev/null; then
        echo -e "${Info} 检测到 apt，尝试安装 netcat..."
        apt-get update -qq 2>/dev/null
        apt-get install -y netcat-openbsd 2>/dev/null || apt-get install -y netcat 2>/dev/null
    elif command -v yum &>/dev/null; then
        echo -e "${Info} 检测到 yum，尝试安装 ncat..."
        yum install -y nmap-ncat 2>/dev/null || yum install -y nc 2>/dev/null
    elif command -v dnf &>/dev/null; then
        echo -e "${Info} 检测到 dnf，尝试安装 ncat..."
        dnf install -y nmap-ncat 2>/dev/null
    elif command -v apk &>/dev/null; then
        echo -e "${Info} 检测到 apk，尝试安装 netcat..."
        apk add --no-cache netcat-openbsd 2>/dev/null
    elif command -v pacman &>/dev/null; then
        echo -e "${Info} 检测到 pacman，尝试安装 socat..."
        pacman -S --noconfirm socat 2>/dev/null
    elif command -v pkg &>/dev/null; then
        # FreeBSD
        echo -e "${Info} 检测到 pkg (FreeBSD)，尝试安装 socat..."
        pkg install -y socat 2>/dev/null
    else
        echo -e "${Warning} 未检测到支持的包管理器"
        return 1
    fi
    
    # 验证安装
    if command -v nc &>/dev/null || command -v ncat &>/dev/null || command -v socat &>/dev/null; then
        echo -e "${Info} 工具安装成功"
        return 0
    else
        return 1
    fi
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
    
    # 初始化数据文件
    get_total_traffic > "$STATS_DIR/stats"
    
    # 启动静态文件服务器
    # 使用 python3 -m http.server 是最稳健的，它会自动服务当前目录下的文件
    # 这里的技巧是：我们cd到STATS_DIR目录启动服务，这样 /stats 就对应了 STATS_DIR/stats 文件
    
    local runner_script="$STATS_DIR/api_runner.sh"
    # 生成主 runner 脚本，负责启动 HTTP 服务和数据更新循环
    cat > "$runner_script" << EOF
#!/bin/bash
STATS_DIR="$STATS_DIR"
MANAGER_SCRIPT="$0"

cd "\$STATS_DIR"

# 启动数据更新循环 (后台)
while true; do
    bash "\$MANAGER_SCRIPT" update >/dev/null 2>&1
    sleep 60
done &
UPDATER_PID=\$!

# 启动 HTTP 服务循环 (前台阻塞)
while true; do
    if command -v python3 &>/dev/null; then
        python3 -m http.server $port > /dev/null 2>&1
    elif command -v python &>/dev/null; then
        python -m http.server $port > /dev/null 2>&1
    elif command -v busybox &>/dev/null; then
        busybox httpd -f -p $port -h "\$STATS_DIR" > /dev/null 2>&1
    else
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n" | cat - stats | nc -l -p $port -q 1
    fi
    sleep 2
done

# 清理后台更新进程
kill \$UPDATER_PID 2>/dev/null
EOF
    chmod +x "$runner_script"
    
    # 尝试使用 crontab (如果可用) 作为双重保障，但如果失败也不阻塞
    if command -v crontab &>/dev/null; then
        (crontab -l 2>/dev/null | grep -v "modules/stats/manager.sh update") | crontab - 2>/dev/null
        (crontab -l 2>/dev/null; echo "* * * * * bash $HOME/vps-play/modules/stats/manager.sh update >/dev/null 2>&1") | crontab - 2>/dev/null
    fi

    # 启动 Runner
    nohup bash "$runner_script" > "$STATS_LOG" 2>&1 &
    local runner_pid=$!
    disown $runner_pid
    echo $runner_pid > "$STATS_PID" # 注意：这里我们要记录 runner 的 PID，而不是 nohup 的返回值（虽然通常是一样的）
    

    
    local pid=$!
    echo $pid > "$STATS_PID"
    echo "$port" > "$STATS_DIR/api_port"
    
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        echo -e "${Info} API 服务已启动 (PID: $pid)"
        local api_url="http://$(curl -s4 ip.sb 2>/dev/null || echo "YOUR_IP"):$port/stats"
        echo -e "${Tip} API 地址: $api_url"
        
        # 检查是否需要启动 Argo (开机自启或交互选择)
        local argo_enabled=0
        if [ -f "$STATS_DIR/argo_enabled" ]; then
            argo_enabled=1
        elif [ -t 0 ]; then
             echo -e ""
             echo -e "${Info} 是否启动 Argo 临时隧道 (穿透内网/Cloudflare)? [y/N]"
             read -p "请选择: " argo_choice
             if [[ "$argo_choice" == "y" || "$argo_choice" == "Y" ]]; then
                 argo_enabled=1
                 touch "$STATS_DIR/argo_enabled"
             fi
        fi

        if [ "$argo_enabled" -eq 1 ]; then
            start_argo_tunnel "$port"
        fi
    else
        echo -e "${Error} API 服务启动失败"
        rm -f "$STATS_PID"
    fi
}

start_argo_tunnel() {
    local port=$1
    local cloudflared_bin="$HOME/.vps-play/app/cloudflared"
    
    # 检测 cloudflared
    if ! [ -f "$cloudflared_bin" ]; then
        echo -e "${Info} 未找到 cloudflared，尝试安装..."
        
        # 独立的下载逻辑，避免调用 argo/manager.sh 的菜单
        local download_url=""
        local arch_name=""
        
        case "$(uname -m)" in
            x86_64|amd64) arch_name="amd64" ;;
            aarch64|arm64) arch_name="arm64" ;;
            armv7l) arch_name="arm" ;;
            i386|i686) arch_name="386" ;;
            *) 
                echo -e "${Error} 不支持的架构: $(uname -m)"; return 1 ;;
        esac
        
        case "$(uname)" in
            Linux) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch_name}" ;;
            FreeBSD) download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-freebsd-${arch_name}" ;;
            *) echo -e "${Error} 不支持的系统: $(uname)"; return 1 ;;
        esac
        
        mkdir -p "$(dirname "$cloudflared_bin")"
        echo -e "${Info} 正在下载: $download_url"
        curl -sL "$download_url" -o "$cloudflared_bin"
        
        if [ ! -s "$cloudflared_bin" ]; then
             echo -e "${Error} 下载失败或文件为空，请检查网络连接"
             rm -f "$cloudflared_bin"
             return 1
        fi
        
        chmod +x "$cloudflared_bin"
    fi
    
    
    if [ -f "$cloudflared_bin" ]; then
        echo -e "${Info} 启动 Argo 隧道..."
        nohup "$cloudflared_bin" tunnel --url "http://127.0.0.1:$port" --no-autoupdate > "$STATS_DIR/argo.log" 2>&1 &
        local argo_pid=$!
        disown $argo_pid
        echo $argo_pid > "$STATS_DIR/argo.pid"
        
        echo -e "${Info} 等待获取域名..."
        sleep 5
        local argo_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$STATS_DIR/argo.log" | head -1)
        
        if [ -n "$argo_domain" ]; then
            echo -e "${Success} Argo 隧道启动成功!"
            echo -e "${Tip} Argo API 地址: ${Cyan}${argo_domain}/stats${Reset}"
        else
            echo -e "${Warning} 获取域名超时，请稍后查看日志: $STATS_DIR/argo.log"
        fi
    else
        echo -e "${Error} cloudflared 安装失败"
    fi
}


# Python HTTP 服务器 (优先使用)
start_python_server() {
    local port=$1
    local script_path="$STATS_DIR/api_server.py"
    
    # 生成 Python API 服务器脚本
    cat > "$script_path" << 'PYEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

class StatsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        
        try:
            # 调用 shell 脚本获取流量数据
            result = subprocess.run(
                ['bash', os.path.join(SCRIPT_DIR, '..', 'stats', 'manager.sh'), 'get'],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                self.wfile.write(result.stdout.encode())
            else:
                self.wfile.write(b'{"error": "failed to get stats"}')
        except Exception as e:
            self.wfile.write(json.dumps({"error": str(e)}).encode())
    
    def log_message(self, format, *args):
        pass  # 禁用日志

with socketserver.TCPServer(("", PORT), StatsHandler) as httpd:
    httpd.serve_forever()
PYEOF
    
    chmod +x "$script_path"
    
    # 如果是 generate_only 模式，则不启动
    if [ "$2" = "generate_only" ]; then
        return 0
    fi
    
    # 兼容旧逻辑 (虽然现在主要用 runner)
    if command -v python3 &>/dev/null; then
        nohup python3 "$script_path" "$port" > "$STATS_LOG" 2>&1 &
    else
        nohup python "$script_path" "$port" > "$STATS_LOG" 2>&1 &
    fi
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
        
        if [ -f "$STATS_DIR/argo.pid" ]; then
            kill $(cat "$STATS_DIR/argo.pid") 2>/dev/null
            rm -f "$STATS_DIR/argo.pid"
        fi
        
        # 仅在交互模式下移除 Argo 启用标志，以便开机自启能记住设置
        if [ -t 0 ]; then
             rm -f "$STATS_DIR/argo_enabled"
        fi
        
        # 移除数据刷新 cron
        (crontab -l 2>/dev/null | grep -v "modules/stats/manager.sh update") | crontab -
        
        echo -e "${Info} API 服务已停止"
    else
        echo -e "${Warning} API 服务未运行"
    fi
}

# 配置开机自启
setup_autostart() {
    local port=$(cat "$STATS_DIR/api_port" 2>/dev/null || echo "30000")
    
    echo -e ""
    echo -e "${Cyan}========== 配置开机自启 ==========${Reset}"
    
    # 检查是否有 systemd
    if command -v systemctl &>/dev/null && [ -d /etc/systemd/system ]; then
        echo -e "${Info} 检测到 systemd，配置系统服务..."
        
        cat > /etc/systemd/system/vps-stats-api.service << EOF
[Unit]
Description=VPS-play Traffic Stats API
After=network.target

[Service]
Type=simple
ExecStart=$STATS_DIR/api_server.py $port
Restart=always
RestartSec=5
User=root
WorkingDirectory=$STATS_DIR

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable vps-stats-api
        systemctl start vps-stats-api
        
        echo -e "${Info} systemd 服务已配置并启动"
        echo -e "${Tip} 管理命令: systemctl {start|stop|status} vps-stats-api"
    else
        # 使用 cron @reboot
        echo -e "${Info} 使用 cron 配置开机自启..."
        
        local startup_script="$STATS_DIR/startup.sh"
        cat > "$startup_script" << EOF
#!/bin/bash
# VPS-play Stats API 自启动脚本
sleep 10
cd "$STATS_DIR"
nohup bash "$HOME/vps-play/modules/stats/manager.sh" start "$port" > /dev/null 2>&1 &
EOF
        chmod +x "$startup_script"
        
        # 添加到 cron
        (crontab -l 2>/dev/null | grep -v "vps-stats-api"; echo "@reboot $startup_script") | crontab -
        
        echo -e "${Info} cron 开机自启已配置"
        echo -e "${Tip} 查看: crontab -l"
    fi
    
    echo -e ""
}

# 移除开机自启
remove_autostart() {
    echo -e "${Info} 移除开机自启配置..."
    
    # 移除 systemd 服务
    if [ -f /etc/systemd/system/vps-stats-api.service ]; then
        systemctl stop vps-stats-api 2>/dev/null
        systemctl disable vps-stats-api 2>/dev/null
        rm -f /etc/systemd/system/vps-stats-api.service
        systemctl daemon-reload
        echo -e "${Info} systemd 服务已移除"
    fi
    
    # 移除 cron
    crontab -l 2>/dev/null | grep -v "vps-stats-api" | crontab -
    rm -f "$STATS_DIR/startup.sh"
    
    echo -e "${Info} 开机自启已移除"
}

# 直接启动 API (用于命令行参数)
direct_start_api() {
    local port=$1
    start_api_server "$port"
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
    
    # 使用 sed 解析 JSON (兼容 FreeBSD)
    local upload=$(echo "$traffic" | sed -n 's/.*"upload"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    local download=$(echo "$traffic" | sed -n 's/.*"download"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    local used=$(echo "$traffic" | sed -n 's/.*"used"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    local total=$(echo "$traffic" | sed -n 's/.*"total"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    local remaining=$(echo "$traffic" | sed -n 's/.*"remaining"[[:space:]]*:[[:space:]]*\(-*[0-9]*\).*/\1/p' | head -1)
    local interface=$(echo "$traffic" | sed -n 's/.*"interface"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    
    upload=${upload:-0}
    download=${download:-0}
    used=${used:-0}
    total=${total:-0}
    remaining=${remaining:-0}

    
    # 转换为可读格式 (纯bash，不依赖bc)
    format_bytes() {
        local bytes=$1
        [ -z "$bytes" ] && bytes=0
        
        if [ $bytes -ge 1073741824 ]; then
            local gb=$((bytes / 1073741824))
            local mb=$(((bytes % 1073741824) * 100 / 1073741824))
            printf "%d.%02d GB" $gb $mb
        elif [ $bytes -ge 1048576 ]; then
            local mb=$((bytes / 1048576))
            local kb=$(((bytes % 1048576) * 100 / 1048576))
            printf "%d.%02d MB" $mb $kb
        elif [ $bytes -ge 1024 ]; then
            local kb=$((bytes / 1024))
            local b=$(((bytes % 1024) * 100 / 1024))
            printf "%d.%02d KB" $kb $b
        else
            echo "$bytes B"
        fi
    }
    
    echo -e " 网络接口: ${Cyan}${interface:-未知}${Reset}"
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
        echo -e " ${Green}6.${Reset}  配置开机自启"
        echo -e " ${Green}7.${Reset}  移除开机自启"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回"
        echo -e "${Green}===================================================${Reset}"
        
        read -p " 请选择 [0-7]: " choice
        
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
            6) setup_autostart ;;
            7) remove_autostart ;;
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
        update)
            # 仅生成 stats 文件 (用于 cron)
            get_total_traffic > "$STATS_DIR/stats"
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
