#!/bin/bash
# sing-box 模块 - VPS-play
# 多协议代理节点管理
# 参考: Misaka-blog/hysteria-install, Misaka-blog/tuic-script

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -z "$MODULE_DIR" ] && MODULE_DIR="$HOME/vps-play/modules/singbox"
VPSPLAY_DIR="$(cd "$MODULE_DIR/../.." 2>/dev/null && pwd)"
[ -z "$VPSPLAY_DIR" ] && VPSPLAY_DIR="$HOME/vps-play"

[ -f "$VPSPLAY_DIR/utils/env_detect.sh" ] && source "$VPSPLAY_DIR/utils/env_detect.sh"
[ -f "$VPSPLAY_DIR/utils/port_manager.sh" ] && source "$VPSPLAY_DIR/utils/port_manager.sh"
[ -f "$VPSPLAY_DIR/utils/process_manager.sh" ] && source "$VPSPLAY_DIR/utils/process_manager.sh"
[ -f "$VPSPLAY_DIR/utils/network.sh" ] && source "$VPSPLAY_DIR/utils/network.sh"

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
SINGBOX_DIR="$HOME/.vps-play/singbox"
SINGBOX_BIN="$SINGBOX_DIR/sing-box"
SINGBOX_CONF="$SINGBOX_DIR/config.json"
SINGBOX_LOG="$SINGBOX_DIR/sing-box.log"
CERT_DIR="$SINGBOX_DIR/cert"


# sing-box 版本
SINGBOX_VERSION="1.10.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$SINGBOX_DIR" "$CERT_DIR"

# ==================== 系统检测 ====================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add")

detect_system() {
    if [ -z "$OS_DISTRO" ]; then
        for i in /etc/os-release /etc/lsb-release /etc/redhat-release; do
            [ -f "$i" ] && SYS=$(cat "$i" | tr '[:upper:]' '[:lower:]')
        done
        
        for ((int = 0; int < ${#REGEX[@]}; int++)); do
            if [[ $SYS =~ ${REGEX[int]} ]]; then
                SYSTEM="${RELEASE[int]}"
                PKG_UPDATE="${PACKAGE_UPDATE[int]}"
                PKG_INSTALL="${PACKAGE_INSTALL[int]}"
                break
            fi
        done
    fi
}

# ==================== 获取 IP ====================
get_ip() {
    ip=$(curl -s4m5 ip.sb 2>/dev/null) || ip=$(curl -s6m5 ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip="$PUBLIC_IP"
    echo "$ip"
}

# ==================== 证书管理 ====================
generate_self_signed_cert() {
    local domain=${1:-www.bing.com}
    
    echo -e "${Info} 生成自签名证书 (域名: $domain)..."
    
    openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/private.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$CERT_DIR/private.key" -out "$CERT_DIR/cert.crt" -subj "/CN=$domain" 2>/dev/null
    
    chmod 644 "$CERT_DIR/cert.crt" "$CERT_DIR/private.key"
    
    echo -e "${Info} 证书生成完成"
    echo -e " 证书路径: ${Cyan}$CERT_DIR/cert.crt${Reset}"
    echo -e " 私钥路径: ${Cyan}$CERT_DIR/private.key${Reset}"
}

apply_acme_cert() {
    echo -e "${Info} 使用 ACME 申请真实证书"
    
    read -p "请输入域名: " domain
    [ -z "$domain" ] && { echo -e "${Error} 域名不能为空"; return 1; }
    
    # 检查域名解析
    local domain_ip=$(dig +short "$domain" 2>/dev/null | head -1)
    local server_ip=$(get_ip)
    
    if [ "$domain_ip" != "$server_ip" ]; then
        echo -e "${Warning} 域名解析的 IP ($domain_ip) 与服务器 IP ($server_ip) 不匹配"
        read -p "是否继续? [y/N]: " continue_acme
        [[ ! $continue_acme =~ ^[Yy]$ ]] && return 1
    fi
    
    # 安装 acme.sh
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo -e "${Info} 安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=$(date +%s)@gmail.com
    fi
    
    # 申请证书
    echo -e "${Info} 申请证书..."
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --insecure
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$CERT_DIR/private.key" \
        --fullchain-file "$CERT_DIR/cert.crt" \
        --ecc
    
    if [ -f "$CERT_DIR/cert.crt" ] && [ -s "$CERT_DIR/cert.crt" ]; then
        echo "$domain" > "$CERT_DIR/domain.txt"
        echo -e "${Info} 证书申请成功"
        return 0
    else
        echo -e "${Error} 证书申请失败"
        return 1
    fi
}

cert_menu() {
    echo -e ""
    echo -e "${Info} 证书申请方式:"
    echo -e " ${Green}1.${Reset} 自签名证书 (默认，推荐)"
    echo -e " ${Green}2.${Reset} ACME 申请真实证书"
    echo -e " ${Green}3.${Reset} 使用已有证书"
    
    read -p "请选择 [1-3]: " cert_choice
    cert_choice=${cert_choice:-1}
    
    case "$cert_choice" in
        1)
            read -p "伪装域名 [www.bing.com]: " fake_domain
            fake_domain=${fake_domain:-www.bing.com}
            generate_self_signed_cert "$fake_domain"
            CERT_DOMAIN="$fake_domain"
            ;;
        2)
            apply_acme_cert
            CERT_DOMAIN=$(cat "$CERT_DIR/domain.txt" 2>/dev/null)
            ;;
        3)
            read -p "证书路径: " custom_cert
            read -p "私钥路径: " custom_key
            [ -f "$custom_cert" ] && cp "$custom_cert" "$CERT_DIR/cert.crt"
            [ -f "$custom_key" ] && cp "$custom_key" "$CERT_DIR/private.key"
            read -p "证书域名: " CERT_DOMAIN
            ;;
    esac
}

# ==================== 端口配置 ====================
config_port() {
    local proto_name=$1
    local default_port=$2
    
    echo -e ""
    read -p "设置 $proto_name 端口 [留空随机]: " port
    
    if [ -z "$port" ]; then
        port=$(shuf -i 10000-65535 -n 1)
    fi
    
    # 检查端口是否被占用
    while ss -tunlp 2>/dev/null | grep -qw ":$port "; do
        echo -e "${Warning} 端口 $port 已被占用"
        port=$(shuf -i 10000-65535 -n 1)
        echo -e "${Info} 自动分配新端口: $port"
    done
    
    echo -e "${Info} 使用端口: ${Cyan}$port${Reset}"
    echo "$port"
}

# ==================== 下载安装 ====================
download_singbox() {
    echo -e "${Info} 正在下载 sing-box v${SINGBOX_VERSION}..."
    
    local os_type="linux"
    local arch_type="amd64"
    
    case "$OS_TYPE" in
        freebsd) os_type="freebsd" ;;
        linux) os_type="linux" ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64" ;;
        aarch64|arm64) arch_type="arm64" ;;
        armv7l) arch_type="armv7" ;;
    esac
    
    local download_url="${SINGBOX_REPO}/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-${os_type}-${arch_type}.tar.gz"
    
    cd "$SINGBOX_DIR"
    
    curl -sL "$download_url" -o sing-box.tar.gz
    tar -xzf sing-box.tar.gz --strip-components=1
    rm -f sing-box.tar.gz
    chmod +x sing-box
    
    if [ -f "$SINGBOX_BIN" ]; then
        echo -e "${Info} sing-box 下载完成"
        $SINGBOX_BIN version
    else
        echo -e "${Error} 下载失败"
        return 1
    fi
}

# ==================== Hysteria2 配置 ====================
install_hysteria2() {
    echo -e ""
    echo -e "${Cyan}========== 安装 Hysteria2 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 配置证书
    cert_menu
    
    # 配置端口
    local port=$(config_port "Hysteria2")
    
    # 配置密码
    read -p "设置密码 [留空随机生成]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 端口跳跃
    echo -e ""
    echo -e "${Info} 是否启用端口跳跃?"
    echo -e " ${Green}1.${Reset} 否，单端口 (默认)"
    echo -e " ${Green}2.${Reset} 是，端口跳跃"
    read -p "请选择 [1-2]: " jump_choice
    
    local port_hopping=""
    if [ "$jump_choice" = "2" ]; then
        read -p "起始端口: " start_port
        read -p "结束端口: " end_port
        if [ -n "$start_port" ] && [ -n "$end_port" ]; then
            # 设置 iptables 规则
            iptables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            ip6tables -t nat -A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-ports $port 2>/dev/null
            port_hopping="${start_port}-${end_port}"
            echo -e "${Info} 端口跳跃已配置: $port_hopping -> $port"
        fi
    fi
    
    # 生成配置
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "password": "$password"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.crt",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 保存节点信息
    local server_ip=$(get_ip)
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
协议: Hysteria2
地址: $server_ip
端口: ${port_hopping:-$port}
密码: $password
SNI: ${CERT_DOMAIN:-www.bing.com}
跳过证书验证: true
EOF

    # 生成分享链接
    local hy2_link="hysteria2://${password}@${server_ip}:${port_hopping:-$port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-${server_ip}"
    echo "$hy2_link" > "$SINGBOX_DIR/hy2_link.txt"

    echo -e ""
    echo -e "${Green}========== Hysteria2 安装完成 ==========${Reset}"
    echo -e " 地址: ${Cyan}${server_ip}${Reset}"
    echo -e " 端口: ${Cyan}${port_hopping:-$port}${Reset}"
    echo -e " 密码: ${Cyan}${password}${Reset}"
    echo -e " SNI:  ${Cyan}${CERT_DOMAIN:-www.bing.com}${Reset}"
    echo -e ""
    echo -e " 分享链接:"
    echo -e " ${Yellow}${hy2_link}${Reset}"
    echo -e "${Green}=========================================${Reset}"
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== TUIC 配置 ====================
install_tuic() {
    echo -e ""
    echo -e "${Cyan}========== 安装 TUIC 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 配置证书
    cert_menu
    
    # 配置端口
    local port=$(config_port "TUIC")
    
    # 配置 UUID 和密码
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 12)")
    read -p "设置密码 [留空随机生成]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 拥塞控制
    echo -e ""
    echo -e "${Info} 选择拥塞控制算法:"
    echo -e " ${Green}1.${Reset} bbr (默认)"
    echo -e " ${Green}2.${Reset} cubic"
    echo -e " ${Green}3.${Reset} new_reno"
    read -p "请选择 [1-3]: " cc_choice
    
    local congestion="bbr"
    case "$cc_choice" in
        2) congestion="cubic" ;;
        3) congestion="new_reno" ;;
    esac
    
    # 生成配置
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "password": "$password"
        }
      ],
      "congestion_control": "$congestion",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CERT_DIR/cert.crt",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 保存节点信息
    local server_ip=$(get_ip)
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
协议: TUIC v5
地址: $server_ip
端口: $port
UUID: $uuid
密码: $password
拥塞控制: $congestion
SNI: ${CERT_DOMAIN:-www.bing.com}
跳过证书验证: true
EOF

    # 生成分享链接
    local tuic_link="tuic://${uuid}:${password}@${server_ip}:${port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=${congestion}&alpn=h3&udp_relay_mode=native&allow_insecure=1#TUIC-${server_ip}"
    echo "$tuic_link" > "$SINGBOX_DIR/tuic_link.txt"

    echo -e ""
    echo -e "${Green}========== TUIC 安装完成 ==========${Reset}"
    echo -e " 地址: ${Cyan}${server_ip}${Reset}"
    echo -e " 端口: ${Cyan}${port}${Reset}"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " 密码: ${Cyan}${password}${Reset}"
    echo -e " 拥塞控制: ${Cyan}${congestion}${Reset}"
    echo -e ""
    echo -e " 分享链接:"
    echo -e " ${Yellow}${tuic_link}${Reset}"
    echo -e "${Green}=========================================${Reset}"
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== VLESS Reality 配置 ====================
install_vless_reality() {
    echo -e ""
    echo -e "${Cyan}========== 安装 VLESS Reality 节点 ==========${Reset}"
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 配置端口
    local port=$(config_port "VLESS Reality")
    
    # 生成 UUID
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    
    # Reality 配置
    echo -e ""
    read -p "目标网站 (dest) [www.microsoft.com]: " dest
    dest=${dest:-www.microsoft.com}
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 生成 Reality 密钥对
    echo -e "${Info} 生成 Reality 密钥对..."
    local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
    local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
    
    # 生成 Short ID
    local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
    
    # 生成配置
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 保存节点信息
    local server_ip=$(get_ip)
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
协议: VLESS Reality
地址: $server_ip
端口: $port
UUID: $uuid
Flow: xtls-rprx-vision
SNI: $server_name
公钥: $public_key
Short ID: $short_id
EOF

    # 生成分享链接
    local vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-Reality-${server_ip}"
    echo "$vless_link" > "$SINGBOX_DIR/vless_link.txt"

    echo -e ""
    echo -e "${Green}========== VLESS Reality 安装完成 ==========${Reset}"
    echo -e " 地址: ${Cyan}${server_ip}${Reset}"
    echo -e " 端口: ${Cyan}${port}${Reset}"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " SNI:  ${Cyan}${server_name}${Reset}"
    echo -e " 公钥: ${Cyan}${public_key}${Reset}"
    echo -e " Short ID: ${Cyan}${short_id}${Reset}"
    echo -e ""
    echo -e " 分享链接:"
    echo -e " ${Yellow}${vless_link}${Reset}"
    echo -e "${Green}=========================================${Reset}"
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== 服务管理 ====================
start_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Error} sing-box 未安装"
        return 1
    fi
    
    if [ ! -f "$SINGBOX_CONF" ]; then
        echo -e "${Error} 配置文件不存在"
        return 1
    fi
    
    echo -e "${Info} 启动 sing-box..."
    
    # 使用 systemd 或 nohup
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        # 创建 systemd 服务
        cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
Type=simple
ExecStart=$SINGBOX_BIN run -c $SINGBOX_CONF
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box
        systemctl start sing-box
        
        sleep 2
        if systemctl is-active sing-box &>/dev/null; then
            echo -e "${Info} sing-box 启动成功 (systemd)"
        else
            echo -e "${Error} 启动失败"
            systemctl status sing-box
        fi
    else
        # 使用 nohup
        start_process "singbox" "$SINGBOX_BIN run -c $SINGBOX_CONF" "$SINGBOX_DIR"
    fi
}

stop_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 未安装"
        return 1
    fi
    
    if ! pgrep -f "sing-box" &>/dev/null; then
        echo -e "${Warning} sing-box 未在运行"
        return 0
    fi
    
    echo -e "${Info} 停止 sing-box..."
    
    if [ "$HAS_SYSTEMD" = true ] && [ "$HAS_ROOT" = true ]; then
        systemctl stop sing-box 2>/dev/null
    else
        stop_process "singbox"
    fi
    
    pkill -f "sing-box" 2>/dev/null
    echo -e "${Info} sing-box 已停止"
}

restart_singbox() {
    stop_singbox
    sleep 1
    start_singbox
}

status_singbox() {
    if [ ! -f "$SINGBOX_BIN" ]; then
        echo -e "${Warning} sing-box 未安装"
        echo -e "${Tip} 请先选择 [1-3] 安装节点"
        return 1
    fi
    
    echo -e "${Info} sing-box 状态:"
    
    if pgrep -f "sing-box" &>/dev/null; then
        echo -e "  运行状态: ${Green}运行中${Reset}"
        echo -e "  进程 PID: $(pgrep -f 'sing-box' | head -1)"
    else
        echo -e "  运行状态: ${Red}已停止${Reset}"
    fi
    
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "  配置文件: ${Cyan}$SINGBOX_CONF${Reset}"
    fi
}

# ==================== 节点信息 ====================
show_node_info() {
    if [ -f "$SINGBOX_DIR/node_info.txt" ]; then
        echo -e ""
        echo -e "${Green}==================== 节点信息 ====================${Reset}"
        cat "$SINGBOX_DIR/node_info.txt"
        echo -e "${Green}=================================================${Reset}"
        
        # 显示分享链接
        for link_file in "$SINGBOX_DIR"/*_link.txt; do
            if [ -f "$link_file" ]; then
                echo -e ""
                echo -e "${Info} 分享链接:"
                echo -e "${Yellow}$(cat "$link_file")${Reset}"
            fi
        done
    else
        echo -e "${Warning} 未找到节点配置"
    fi
}

# ==================== 卸载 ====================
uninstall_singbox() {
    echo -e "${Warning} 确定要卸载 sing-box? [y/N]"
    read -p "" confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0
    
    stop_singbox
    
    # 删除 systemd 服务
    if [ -f /etc/systemd/system/sing-box.service ]; then
        systemctl disable sing-box
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
    fi
    
    rm -rf "$SINGBOX_DIR"
    echo -e "${Info} sing-box 已卸载"
}

# ==================== 主菜单 ====================
show_singbox_menu() {
    while true; do
        clear
        echo -e "${Cyan}"
        cat << "EOF"
    ╔═╗╦╔╗╔╔═╗   ╔╗ ╔═╗═╗ ╦
    ╚═╗║║║║║ ╦───╠╩╗║ ║╔╩╦╝
    ╚═╝╩╝╚╝╚═╝   ╚═╝╚═╝╩ ╚═
    多协议代理节点
EOF
        echo -e "${Reset}"
        
        # 显示状态
        if [ -f "$SINGBOX_BIN" ]; then
            echo -e " 安装状态: ${Green}已安装${Reset}"
            if pgrep -f "sing-box" &>/dev/null; then
                echo -e " 运行状态: ${Green}运行中${Reset}"
            else
                echo -e " 运行状态: ${Red}已停止${Reset}"
            fi
        else
            echo -e " 安装状态: ${Yellow}未安装${Reset}"
        fi
        echo -e ""
        
        echo -e "${Green}==================== sing-box 管理 ====================${Reset}"
        echo -e " ${Yellow}安装节点${Reset}"
        echo -e " ${Green}1.${Reset}  Hysteria2 (推荐)"
        echo -e " ${Green}2.${Reset}  TUIC v5"
        echo -e " ${Green}3.${Reset}  VLESS Reality"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}管理${Reset}"
        echo -e " ${Green}4.${Reset}  启动"
        echo -e " ${Green}5.${Reset}  停止"
        echo -e " ${Green}6.${Reset}  重启"
        echo -e " ${Green}7.${Reset}  查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}8.${Reset}  查看节点信息"
        echo -e " ${Green}9.${Reset}  查看配置文件"
        echo -e " ${Green}10.${Reset} 卸载 sing-box"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-10]: " choice
        
        case "$choice" in
            1) install_hysteria2 ;;
            2) install_tuic ;;
            3) install_vless_reality ;;
            4) start_singbox ;;
            5) stop_singbox ;;
            6) restart_singbox ;;
            7) status_singbox ;;
            8) show_node_info ;;
            9) [ -f "$SINGBOX_CONF" ] && cat "$SINGBOX_CONF" || echo -e "${Warning} 配置不存在" ;;
            10) uninstall_singbox ;;
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
    detect_system
    show_singbox_menu
fi
