#!/bin/bash
# sing-box 模块 - VPS-play
# 多协议代理节点管理
# 参考: Misaka-blog/hysteria-install, Misaka-blog/tuic-script
#
# Copyright (C) 2025 VPS-play Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# AnyTLS 协议实现参考了 GPL-3.0 许可的 argosbx 项目
# https://github.com/yonggekkk/argosbx

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
CONFIG_DIR="$SINGBOX_DIR/config"

# 流量统计 API 端口 (clash_api)
SINGBOX_API_PORT=9090

# sing-box 版本
SINGBOX_VERSION="1.12.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box"

mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"

# 生成 experimental 配置块 (可选，目前不使用)
# 流量统计已改为读取 VPS 系统网络接口流量
get_experimental_config() {
    # 返回空，不添加 experimental 配置
    echo ""
}

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
    
    echo -e "" >&2
    # read -p 输出默认就是 stderr，所以不用改
    read -p "设置 $proto_name 端口 [留空随机]: " port
    
    if [ -z "$port" ]; then
        port=$(shuf -i 10000-65535 -n 1)
    fi
    
    # 检查端口是否被占用
    while ss -tunlp 2>/dev/null | grep -qw ":$port "; do
        echo -e "${Warning} 端口 $port 已被占用" >&2
        port=$(shuf -i 10000-65535 -n 1)
        echo -e "${Info} 自动分配新端口: $port" >&2
    done
    
    echo -e "${Info} 使用端口: ${Cyan}$port${Reset}" >&2
    echo "$port"
}

# ==================== 下载安装 ====================
# 获取当前安装版本
get_version() {
    if [ -f "$SINGBOX_BIN" ]; then
        $SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}'
    else
        echo ""
    fi
}

# 版本比较函数 (大于等于)
version_ge() {
    # 如果版本相同
    [ "$1" = "$2" ] && return 0
    
    # 尝试使用 sort -V
    if sort -V </dev/null >/dev/null 2>&1; then
        [ "$(echo -e "$1\n$2" | sort -V | head -n1)" = "$2" ]
    else
        # 手动解析版本号 (awk)
        # 假设版本号格式为 x.y.z
        local v1=$(echo "$1" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
        local v2=$(echo "$2" | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')
        [ "$v1" -ge "$v2" ] 2>/dev/null
    fi
}

download_singbox() {
    local target_version=${1:-$SINGBOX_VERSION}
    echo -e "${Info} 正在下载 sing-box v${target_version}..."
    
    # 确保目录存在
    mkdir -p "$SINGBOX_DIR" "$CERT_DIR" "$CONFIG_DIR"
    
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
    
    local download_url="${SINGBOX_REPO}/releases/download/v${target_version}/sing-box-${target_version}-${os_type}-${arch_type}.tar.gz"
    
    cd "$SINGBOX_DIR" || { echo -e "${Error} 无法进入目录"; return 1; }
    
    # 备份旧版本
    [ -f "$SINGBOX_BIN" ] && mv "$SINGBOX_BIN" "${SINGBOX_BIN}.bak"
    
    curl -sL "$download_url" -o sing-box.tar.gz
    tar -xzf sing-box.tar.gz --strip-components=1
    rm -f sing-box.tar.gz
    chmod +x sing-box
    
    if [ -f "$SINGBOX_BIN" ]; then
        echo -e "${Info} sing-box 下载完成"
        $SINGBOX_BIN version
    else
        echo -e "${Error} 下载失败，还原旧版本..."
        [ -f "${SINGBOX_BIN}.bak" ] && mv "${SINGBOX_BIN}.bak" "$SINGBOX_BIN"
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
    local exp_config=$(get_experimental_config)
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
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


# ==================== AnyTLS 配置 ====================
install_anytls() {
    echo -e ""
    echo -e "${Cyan}========== 安装 AnyTLS 节点 ==========${Reset}"
    
    # 1. 版本检查与升级
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} AnyTLS 需要 sing-box v${min_ver}+ (当前: ${current_ver:-未安装})"
        echo -e "${Info} 正在自动升级内核..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 内核升级失败，无法安装 AnyTLS"
             return 1
        fi
    fi
    
    # 2. 配置端口
    local port=$(config_port "AnyTLS")
    
    # 3. 配置密码
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo -e "${Info} 密码: ${Cyan}$password${Reset}"
    
    # 4. 生成自签证书（AnyTLS 需要 TLS）
    echo -e "${Info} 生成自签证书..."
    local cert_domain="bing.com"
    mkdir -p "$CERT_DIR"
    
    # 方法1: EC prime256v1
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/anytls.key" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" -subj "/CN=$cert_domain" >/dev/null 2>&1
    fi
    
    # 方法2: RSA 2048 (备用)
    if [ ! -f "$CERT_DIR/anytls.key" ]; then
        echo -e "${Warning} EC证书生成失败，尝试RSA备用方法..."
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" >/dev/null 2>&1
    fi
    
    # 方法3: 从 GitHub 下载备用证书
    if [ ! -f "$CERT_DIR/anytls.key" ]; then
        echo -e "${Warning} 本地证书生成失败，正在下载备用证书..."
        curl -sL -o "$CERT_DIR/anytls.key" \
            "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" 2>/dev/null
        curl -sL -o "$CERT_DIR/anytls.crt" \
            "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" 2>/dev/null
    fi
    
    if [ ! -f "$CERT_DIR/anytls.key" ] || [ ! -f "$CERT_DIR/anytls.crt" ]; then
        echo -e "${Error} 证书生成/下载失败"
        return 1
    fi
    
    echo -e "${Info} 证书准备完成"
    
    # 5. 生成配置文件
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
           "password": "$password"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$CERT_DIR/anytls.crt",
        "key_path": "$CERT_DIR/anytls.key"
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
    local hostname=$(hostname 2>/dev/null || echo "vps")
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
协议: AnyTLS
地址: $server_ip
端口: $port
密码: $password
证书: 自签证书
SNI: $cert_domain
说明: 客户端需要安装支持 AnyTLS 的 sing-box (v1.12.0+) 或 Clash Meta
      移动端(小火箭/NekoBox)需启用"允许不安全"或"skip-cert-verify"

OUTBOUND配置示例:
{
  "type": "anytls",
  "tag": "anytls-out",
  "server": "$server_ip",
  "server_port": $port,
  "password": "$password",
  "tls": {
    "enabled": true,
    "server_name": "$cert_domain",
    "insecure": true
  }
}
EOF

    # 生成分享链接（完整格式，兼容 Worker.js 和 sublinkPro）
    local anytls_link="anytls://${password}@${server_ip}:${port}?insecure=1&allowInsecure=1&sni=${cert_domain}&fp=chrome#anytls-${hostname}"
    local out_json="{\"type\":\"anytls\",\"tag\":\"anytls-out\",\"server\":\"$server_ip\",\"server_port\":$port,\"password\":\"$password\",\"tls\":{\"enabled\":true,\"server_name\":\"$cert_domain\",\"insecure\":true}}"
    
    # 保存链接和JSON
    echo "$anytls_link" > "$SINGBOX_DIR/anytls_link.txt"
    echo "$out_json" >> "$SINGBOX_DIR/anytls_link.txt"

    echo -e ""
    echo -e "${Green}========== AnyTLS 安装完成 ==========${Reset}"
    echo -e " 地址: ${Cyan}${server_ip}${Reset}"
    echo -e " 端口: ${Cyan}${port}${Reset}"
    echo -e " 密码: ${Cyan}${password}${Reset}"
    echo -e " SNI:  ${Cyan}${cert_domain}${Reset}"
    echo -e " ${Yellow}证书: 自签证书 (客户端需启用 skip-cert-verify)${Reset}"
    echo -e ""
    echo -e " 分享链接:"
    echo -e " ${Yellow}${anytls_link}${Reset}"
    echo -e ""
    echo -e " JSON配置:"
    echo -e " ${Yellow}${out_json}${Reset}"
    echo -e ""
    echo -e " ${Yellow}请查看 $SINGBOX_DIR/node_info.txt 获取完整配置${Reset}"
    echo -e "${Green}========================================${Reset}"
    
    # 询问是否启动
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# ==================== Any-Reality 配置 (AnyTLS + Reality) ====================
install_any_reality() {
    echo -e ""
    echo -e "${Cyan}========== 安装 Any-Reality 节点 ==========${Reset}"
    echo -e "${Info} Any-Reality 是 AnyTLS 协议与 Reality 的组合"
    
    # 1. 版本检查与升级
    local min_ver="1.12.0"
    local current_ver=""
    
    if [ -f "$SINGBOX_BIN" ]; then
        current_ver=$($SINGBOX_BIN version 2>/dev/null | head -n1 | awk '{print $3}')
    fi
    
    if [ -z "$current_ver" ] || ! version_ge "$current_ver" "$min_ver"; then
        echo -e "${Warning} Any-Reality 需要 sing-box v${min_ver}+ (当前: ${current_ver:-未安装})"
        echo -e "${Info} 正在自动升级内核..."
        download_singbox "$min_ver"
        if [ $? -ne 0 ]; then
             echo -e "${Error} 内核升级失败，无法安装 Any-Reality"
             return 1
        fi
    fi
    
    # 2. 配置端口
    local port=$(config_port "Any-Reality")
    
    # 3. 配置密码
    read -p "设置密码 [留空随机]: " password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo -e "${Info} 密码: ${Cyan}$password${Reset}"
    
    # 4. Reality 配置
    echo -e ""
    read -p "目标网站 (dest) [www.apple.com]: " dest
    dest=${dest:-www.apple.com}
    
    read -p "Server Name [${dest}]: " server_name
    server_name=${server_name:-$dest}
    
    # 5. 生成 Reality 密钥对
    echo -e "${Info} 生成 Reality 密钥对..."
    mkdir -p "$CERT_DIR/reality"
    
    if [ -e "$CERT_DIR/reality/private_key" ]; then
        # 已存在，读取
        private_key=$(cat "$CERT_DIR/reality/private_key")
        public_key=$(cat "$CERT_DIR/reality/public_key")
        short_id=$(cat "$CERT_DIR/reality/short_id")
        echo -e "${Info} 使用已存在的 Reality 密钥"
    else
        # 生成新密钥对
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        private_key=$(echo "$keypair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
        public_key=$(echo "$keypair" | awk '/PublicKey/ {print $2}' | tr -d '"')
        short_id=$($SINGBOX_BIN generate rand --hex 4 2>/dev/null || head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        # 保存
        echo "$private_key" > "$CERT_DIR/reality/private_key"
        echo "$public_key" > "$CERT_DIR/reality/public_key"
        echo "$short_id" > "$CERT_DIR/reality/short_id"
        echo -e "${Info} Reality 密钥生成完成"
    fi
    
    # 6. 生成配置文件
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anyreality-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
           "password": "$password"
        }
      ],
      "padding_scheme": [],
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
    local hostname=$(hostname 2>/dev/null || echo "vps")
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
协议: Any-Reality (AnyTLS + Reality)
地址: $server_ip
端口: $port
密码: $password
目标网站: $dest
SNI: $server_name
公钥: $public_key
Short ID: $short_id
说明: 客户端需要支持 AnyTLS 的 sing-box (v1.12.0+)

OUTBOUND配置示例:
{
  "type": "anytls",
  "tag": "anyreality-out",
  "server": "$server_ip",
  "server_port": $port,
  "password": "$password",
  "tls": {
    "enabled": true,
    "server_name": "$server_name",
    "reality": {
      "enabled": true,
      "public_key": "$public_key",
      "short_id": "$short_id"
    }
  }
}
EOF

    # 生成分享链接（完整格式，兼容 Worker.js 和 sublinkPro）
    local ar_link="anytls://${password}@${server_ip}:${port}?security=reality&sni=${server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#any-reality-${hostname}"
    
    # 保存链接
    echo "$ar_link" > "$SINGBOX_DIR/anyreality_link.txt"

    echo -e ""
    echo -e "${Green}========== Any-Reality 安装完成 ==========${Reset}"
    echo -e " 地址: ${Cyan}${server_ip}${Reset}"
    echo -e " 端口: ${Cyan}${port}${Reset}"
    echo -e " 密码: ${Cyan}${password}${Reset}"
    echo -e " SNI:  ${Cyan}${server_name}${Reset}"
    echo -e " 目标网站: ${Cyan}${dest}${Reset}"
    echo -e " 公钥: ${Cyan}${public_key}${Reset}"
    echo -e " Short ID: ${Cyan}${short_id}${Reset}"
    echo -e ""
    echo -e " 分享链接:"
    echo -e " ${Yellow}${ar_link}${Reset}"
    echo -e ""
    echo -e " ${Yellow}请查看 $SINGBOX_DIR/node_info.txt 获取完整配置${Reset}"
    echo -e "${Green}========================================${Reset}"
    
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
    local exp_config=$(get_experimental_config)
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "name": "user",
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
    read -p "目标网站 (dest) [www.apple.com]: " dest
    dest=${dest:-www.apple.com}
    
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
            echo -e "${Info} 配置检查结果："
            echo -e "===================="
            "$SINGBOX_BIN" check -c "$SINGBOX_CONF" 2>&1 || true
            echo -e "===================="
            echo -e "${Info} systemd 状态："
            systemctl status sing-box --no-pager
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

view_config() {
    if [ -f "$SINGBOX_CONF" ]; then
        echo -e "${Green}==================== 配置文件 ====================${Reset}"
        cat "$SINGBOX_CONF"
        echo -e "${Green}=================================================${Reset}"
    else
        echo -e "${Warning} 配置文件不存在"
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

# ==================== 多协议组合安装 ====================
install_combo() {
    echo -e ""
    echo -e "${Cyan}========== 自定义多协议组合 ==========${Reset}"
    echo -e "${Tip} 选择要安装的协议组合，支持同时运行多个协议"
    echo -e ""
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 协议选择
    echo -e "${Info} 请选择要启用的协议 (多选，用逗号分隔):"
    echo -e " ${Green}1.${Reset} Hysteria2"
    echo -e " ${Green}2.${Reset} TUIC v5"
    echo -e " ${Green}3.${Reset} VLESS Reality"
    echo -e " ${Green}4.${Reset} Shadowsocks"
    echo -e " ${Green}5.${Reset} Trojan"
    echo -e " ${Green}6.${Reset} AnyTLS"
    echo -e " ${Green}7.${Reset} Any-Reality"
    echo -e ""
    echo -e " ${Cyan}示例: 1,3,7 表示安装 Hysteria2 + VLESS + Any-Reality${Reset}"
    echo -e ""
    
    read -p "请选择 [1-7]: " combo_choice
    
    if [ -z "$combo_choice" ]; then
        echo -e "${Error} 未选择任何协议"
        return 1
    fi
    
    # 解析选择
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    local install_anytls=false
    local install_any_reality=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
            6) install_anytls=true ;;
            7) install_any_reality=true ;;
        esac
    done
    
    # AnyTLS/Any-Reality 版本检查
    if [ "$install_anytls" = true ] || [ "$install_any_reality" = true ]; then
        if ! version_ge "$(get_version)" "1.12.0"; then
            echo -e "${Info} AnyTLS/Any-Reality 需要升级 sing-box 到 1.12.0+，正在自动升级..."
            download_singbox "1.12.0"
        fi
    fi
    
    # 配置证书 (Hysteria2, TUIC, Trojan 需要)
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        echo -e ""
        echo -e "${Info} 检测到需要 TLS 证书的协议"
        cert_menu
    fi
    
    # 生成统一的 UUID 和密码
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 4)-$(head /dev/urandom | tr -dc a-f0-9 | head -c 12)")
    local password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    echo -e ""
    echo -e "${Info} 统一认证信息:"
    echo -e " UUID: ${Cyan}${uuid}${Reset}"
    echo -e " 密码: ${Cyan}${password}${Reset}"
    echo -e ""
    
    # 端口配置方式
    echo -e "${Info} 端口配置方式:"
    echo -e " ${Green}1.${Reset} 自动分配随机端口 (推荐)"
    echo -e " ${Green}2.${Reset} 手动指定端口"
    read -p "请选择 [1-2]: " port_mode
    
    local hy2_port=""
    local tuic_port=""
    local vless_port=""
    local ss_port=""
    local trojan_port=""
    local anytls_port=""
    local ar_port=""
    
    if [ "$port_mode" = "2" ]; then
        # 手动指定端口
        echo -e ""
        echo -e "${Info} 请为每个协议指定端口 (留空跳过):"
        
        if [ "$install_hy2" = true ]; then
            read -p "Hysteria2 端口: " hy2_port
            [ -z "$hy2_port" ] && hy2_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_tuic" = true ]; then
            read -p "TUIC 端口: " tuic_port
            [ -z "$tuic_port" ] && tuic_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_vless" = true ]; then
            read -p "VLESS Reality 端口: " vless_port
            [ -z "$vless_port" ] && vless_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_ss" = true ]; then
            read -p "Shadowsocks 端口: " ss_port
            [ -z "$ss_port" ] && ss_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_trojan" = true ]; then
            read -p "Trojan 端口: " trojan_port
            [ -z "$trojan_port" ] && trojan_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_anytls" = true ]; then
            read -p "AnyTLS 端口: " anytls_port
            [ -z "$anytls_port" ] && anytls_port=$(shuf -i 10000-65535 -n 1)
        fi
        
        if [ "$install_any_reality" = true ]; then
            read -p "Any-Reality 端口: " ar_port
            [ -z "$ar_port" ] && ar_port=$(shuf -i 10000-65535 -n 1)
        fi
    else
        # 自动分配
        local base_port=$(shuf -i 10000-50000 -n 1)
        [ "$install_hy2" = true ] && hy2_port=$((base_port))
        [ "$install_tuic" = true ] && tuic_port=$((base_port + 1))
        [ "$install_vless" = true ] && vless_port=$((base_port + 2))
        [ "$install_ss" = true ] && ss_port=$((base_port + 3))
        [ "$install_trojan" = true ] && trojan_port=$((base_port + 4))
        [ "$install_anytls" = true ] && anytls_port=$((base_port + 5))
        [ "$install_any_reality" = true ] && ar_port=$((base_port + 6))
    fi
    
    echo -e ""
    echo -e "${Info} 端口分配:"
    [ -n "$hy2_port" ] && echo -e " Hysteria2: ${Cyan}${hy2_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " Shadowsocks: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    [ -n "$ar_port" ] && echo -e " Any-Reality: ${Cyan}${ar_port}${Reset}"
    [ -n "$vless_port" ] && echo -e " VLESS: ${Cyan}${vless_port}${Reset}"
    [ -n "$ss_port" ] && echo -e " SS: ${Cyan}${ss_port}${Reset}"
    [ -n "$trojan_port" ] && echo -e " Trojan: ${Cyan}${trojan_port}${Reset}"
    [ -n "$anytls_port" ] && echo -e " AnyTLS: ${Cyan}${anytls_port}${Reset}"
    
    # 构建配置
    local inbounds=""
    local server_ip=$(get_ip)
    local node_info=""
    local links=""
    
    # Hysteria2 配置
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"hysteria2\",
      \"tag\": \"hy2-in\",
      \"listen\": \"::\",
      \"listen_port\": ${hy2_port},
      \"users\": [
        {
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.crt\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}
[Hysteria2]
端口: ${hy2_port}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
hysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2-${server_ip}"
    fi
    
    # TUIC 配置
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"tuic\",
      \"tag\": \"tuic-in\",
      \"listen\": \"::\",
      \"listen_port\": ${tuic_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"password\": \"${password}\"
        }
      ],
      \"congestion_control\": \"bbr\",
      \"tls\": {
        \"enabled\": true,
        \"alpn\": [\"h3\"],
        \"certificate_path\": \"${CERT_DIR}/cert.crt\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[TUIC v5]
端口: ${tuic_port}
UUID: ${uuid}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
tuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&udp_relay_mode=native&allow_insecure=1#TUIC-${server_ip}"
    fi
    
    # VLESS Reality 配置
    if [ "$install_vless" = true ]; then
        echo -e "${Info} 生成 Reality 密钥..."
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
        local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
        local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        local dest="www.apple.com"
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"vless\",
      \"tag\": \"vless-in\",
      \"listen\": \"::\",
      \"listen_port\": ${vless_port},
      \"users\": [
        {
          \"name\": \"user\",
          \"uuid\": \"${uuid}\",
          \"flow\": \"xtls-rprx-vision\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${dest}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      }
    }"
        
        node_info="${node_info}

[VLESS Reality]
端口: ${vless_port}
UUID: ${uuid}
SNI: ${dest}
公钥: ${public_key}
Short ID: ${short_id}"
        
        links="${links}
vless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${dest}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality-${server_ip}"
    fi
    
    # Shadowsocks 配置
    if [ "$install_ss" = true ]; then
        local ss_method="2022-blake3-aes-256-gcm"
        local ss_password=$(openssl rand -base64 32 2>/dev/null || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 | base64)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"shadowsocks\",
      \"tag\": \"ss-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ss_port},
      \"method\": \"${ss_method}\",
      \"password\": \"${ss_password}\"
    }"
        
        node_info="${node_info}

[Shadowsocks]
端口: ${ss_port}
加密方式: ${ss_method}
密码: ${ss_password}"
        
        local ss_userinfo=$(echo -n "${ss_method}:${ss_password}" | base64 -w0)
        links="${links}
ss://${ss_userinfo}@${server_ip}:${ss_port}#SS-${server_ip}"
    fi
    
    # Trojan 配置
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"trojan\",
      \"tag\": \"trojan-in\",
      \"listen\": \"::\",
      \"listen_port\": ${trojan_port},
      \"users\": [
        {
          \"password\": \"${password}\"
        }
      ],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"${CERT_DIR}/cert.crt\",
        \"key_path\": \"${CERT_DIR}/private.key\"
      }
    }"
        
        node_info="${node_info}

[Trojan]
端口: ${trojan_port}
密码: ${password}
SNI: ${CERT_DOMAIN:-www.bing.com}"
        
        links="${links}
trojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan-${server_ip}"
    fi
    # AnyTLS 配置
    if [ "$install_anytls" = true ]; then
        # 生成自签证书
        local cert_domain="bing.com"
        openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null || \
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$CERT_DIR/anytls.key" \
            -out "$CERT_DIR/anytls.crt" \
            -days 36500 -nodes \
            -subj "/CN=$cert_domain" 2>/dev/null
        
        local anytls_mixed_port=$(shuf -i 20000-60000 -n 1)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        # 注意: JSON 中引用变量需要小心转义
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"anytls-in\",
      \"listen\": \"::\",
      \"listen_port\": ${anytls_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"tls\": {
        \"enabled\": true,
        \"certificate_path\": \"$CERT_DIR/anytls.crt\",
        \"key_path\": \"$CERT_DIR/anytls.key\"
      },
      \"detour\": \"mixed-in-anytls\"
    },
    {
      \"type\": \"mixed\",
      \"tag\": \"mixed-in-anytls\",
      \"listen\": \"127.0.0.1\",
      \"listen_port\": ${anytls_mixed_port}
    }"
    
    node_info="${node_info}
[AnyTLS]
端口: ${anytls_port}
密码: ${password}
SNI: ${cert_domain}
证书: 自签证书
说明: 需 sing-box 1.12.0+ 或 Clash Meta，客户端需启用 skip-cert-verify"

    # 生成分享链接和JSON
    local anytls_link="anytls://${password}@${server_ip}:${anytls_port}#AnyTLS-${server_ip}"
    local out_json="{\"type\":\"anytls\",\"tag\":\"anytls-out\",\"server\":\"$server_ip\",\"server_port\":$anytls_port,\"password\":\"$password\",\"tls\":{\"enabled\":true,\"server_name\":\"$cert_domain\",\"insecure\":true}}"
    links="${links}
${anytls_link}"
    fi

    # Any-Reality 配置
    if [ "$install_any_reality" = true ]; then
        # 生成/复用 Reality 密钥
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
        local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
        local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        local ar_dest="www.apple.com"
        local ar_server_name="www.apple.com"
        local ar_mixed_port=$(shuf -i 20000-60000 -n 1)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}
    {
      \"type\": \"anytls\",
      \"tag\": \"any-reality-in\",
      \"listen\": \"::\",
      \"listen_port\": ${ar_port},
      \"users\": [{\"password\": \"${password}\"}],
      \"tls\": {
        \"enabled\": true,
        \"server_name\": \"${ar_server_name}\",
        \"reality\": {
          \"enabled\": true,
          \"handshake\": {
            \"server\": \"${ar_dest}\",
            \"server_port\": 443
          },
          \"private_key\": \"${private_key}\",
          \"short_id\": [\"${short_id}\"]
        }
      },
      \"detour\": \"mixed-in-ar\"
    },
    {
      \"type\": \"mixed\",
      \"tag\": \"mixed-in-ar\",
      \"listen\": \"127.0.0.1\",
      \"listen_port\": ${ar_mixed_port}
    }"

        node_info="${node_info}
[Any-Reality]
端口: ${ar_port}
密码: ${password}
SNI: ${ar_server_name}
Short ID: ${short_id}
Public Key: ${public_key}
说明: 指纹(fp)建议使用 chrome"

        local ar_link="anytls://${password}@${server_ip}:${ar_port}?security=reality&sni=${ar_server_name}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Any-Reality-${server_ip}"
        links="${links}
${ar_link}"
    fi
    
    # 生成完整配置
    local exp_config=$(get_experimental_config)
    cat > "$SINGBOX_CONF" << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
${exp_config}  "inbounds": [${inbounds}
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
    local active_protocols=""
    [ "$install_hy2" = true ] && active_protocols="${active_protocols}Hysteria2 "
    [ "$install_tuic" = true ] && active_protocols="${active_protocols}TUIC "
    [ "$install_vless" = true ] && active_protocols="${active_protocols}VLESS "
    [ "$install_ss" = true ] && active_protocols="${active_protocols}SS "
    [ "$install_trojan" = true ] && active_protocols="${active_protocols}Trojan "
    
    cat > "$SINGBOX_DIR/node_info.txt" << EOF
============= 多协议组合节点 =============
服务器: ${server_ip}
启用协议: ${active_protocols}
${node_info}
==========================================
EOF
    
    echo "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 多协议组合安装完成 ==========${Reset}"
    echo -e ""
    echo -e " 服务器: ${Cyan}${server_ip}${Reset}"
    echo -e " 启用协议: ${Green}${active_protocols}${Reset}"
    echo -e ""
    
    [ "$install_hy2" = true ] && echo -e " Hysteria2 端口: ${Cyan}${hy2_port}${Reset}"
    [ "$install_tuic" = true ] && echo -e " TUIC 端口: ${Cyan}${tuic_port}${Reset}"
    [ "$install_vless" = true ] && echo -e " VLESS 端口: ${Cyan}${vless_port}${Reset}"
    [ "$install_ss" = true ] && echo -e " SS 端口: ${Cyan}${ss_port}${Reset}"
    [ "$install_trojan" = true ] && echo -e " Trojan 端口: ${Cyan}${trojan_port}${Reset}"
    
    echo -e ""
    echo -e "${Green}=========================================${Reset}"
    echo -e ""
    echo -e "${Info} 分享链接已保存到: ${Cyan}$SINGBOX_DIR/combo_links.txt${Reset}"
    echo -e ""
    
    # 显示链接
    echo -e "${Yellow}分享链接:${Reset}"
    echo -e "${links}"
    echo -e ""
    
    # 启动服务
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
}

# 预设组合
install_preset_combo() {
    echo -e ""
    echo -e "${Cyan}========== 预设协议组合 ==========${Reset}"
    echo -e ""
    echo -e " ${Green}1.${Reset} 标准组合 (Hysteria2 + TUIC)"
    echo -e "    ${Cyan}适合: 日常使用，UDP 游戏${Reset}"
    echo -e ""
    echo -e " ${Green}2.${Reset} 全能组合 (Hysteria2 + TUIC + VLESS Reality)"
    echo -e "    ${Cyan}适合: 全场景覆盖${Reset}"
    echo -e ""
    echo -e " ${Green}3.${Reset} 免费端口组合 (VLESS Reality + Shadowsocks)"
    echo -e "    ${Cyan}适合: Serv00/无 UDP 环境${Reset}"
    echo -e ""
    echo -e " ${Green}4.${Reset} 完整组合 (全部 5 种协议)"
    echo -e "    ${Cyan}适合: 测试和特殊需求${Reset}"
    echo -e ""
    
    read -p "请选择预设 [1-4]: " preset_choice
    
    case "$preset_choice" in
        1)
            echo "1,2" | { read combo_choice; install_combo_internal "1,2"; }
            ;;
        2)
            install_combo_internal "1,2,3"
            ;;
        3)
            install_combo_internal "3,4"
            ;;
        4)
            install_combo_internal "1,2,3,4,5"
            ;;
        *)
            echo -e "${Error} 无效选择"
            return 1
            ;;
    esac
}

# 内部组合安装函数
install_combo_internal() {
    local combo_choice=$1
    
    # 确保 sing-box 已安装
    [ ! -f "$SINGBOX_BIN" ] && download_singbox
    
    # 解析选择
    IFS=',' read -ra protocols <<< "$combo_choice"
    
    local install_hy2=false
    local install_tuic=false
    local install_vless=false
    local install_ss=false
    local install_trojan=false
    
    for p in "${protocols[@]}"; do
        case "$(echo $p | tr -d ' ')" in
            1) install_hy2=true ;;
            2) install_tuic=true ;;
            3) install_vless=true ;;
            4) install_ss=true ;;
            5) install_trojan=true ;;
        esac
    done
    
    # 配置证书
    if [ "$install_hy2" = true ] || [ "$install_tuic" = true ] || [ "$install_trojan" = true ]; then
        cert_menu
    fi
    
    # 生成认证信息
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    local password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    # 分配端口
    local base_port=$(shuf -i 10000-50000 -n 1)
    local hy2_port=$((base_port))
    local tuic_port=$((base_port + 1))
    local vless_port=$((base_port + 2))
    local ss_port=$((base_port + 3))
    local trojan_port=$((base_port + 4))
    
    local server_ip=$(get_ip)
    local inbounds=""
    local links=""
    
    # 构建配置 (简化版，复用上面的逻辑)
    if [ "$install_hy2" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"hysteria2\",\"tag\":\"hy2\",\"listen\":\"::\",\"listen_port\":${hy2_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.crt\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\nhysteria2://${password}@${server_ip}:${hy2_port}?sni=${CERT_DOMAIN:-www.bing.com}&insecure=1#Hy2"
    fi
    
    if [ "$install_tuic" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"tuic\",\"tag\":\"tuic\",\"listen\":\"::\",\"listen_port\":${tuic_port},\"users\":[{\"uuid\":\"${uuid}\",\"password\":\"${password}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_DIR}/cert.crt\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntuic://${uuid}:${password}@${server_ip}:${tuic_port}?sni=${CERT_DOMAIN:-www.bing.com}&congestion_control=bbr&alpn=h3&allow_insecure=1#TUIC"
    fi
    
    if [ "$install_vless" = true ]; then
        local keypair=$($SINGBOX_BIN generate reality-keypair 2>/dev/null)
        local private_key=$(echo "$keypair" | grep -i "privatekey" | awk '{print $2}')
        local public_key=$(echo "$keypair" | grep -i "publickey" | awk '{print $2}')
        local short_id=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)
        
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"vless\",\"tag\":\"vless\",\"listen\":\"::\",\"listen_port\":${vless_port},\"users\":[{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\"}],\"tls\":{\"enabled\":true,\"server_name\":\"www.apple.com\",\"reality\":{\"enabled\":true,\"handshake\":{\"server\":\"www.apple.com\",\"server_port\":443},\"private_key\":\"${private_key}\",\"short_id\":[\"${short_id}\"]}}}"
        links="${links}\nvless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#VLESS-Reality"
    fi
    
    if [ "$install_ss" = true ]; then
        local ss_pass=$(openssl rand -base64 32 2>/dev/null)
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"shadowsocks\",\"tag\":\"ss\",\"listen\":\"::\",\"listen_port\":${ss_port},\"method\":\"2022-blake3-aes-256-gcm\",\"password\":\"${ss_pass}\"}"
        local ss_ui=$(echo -n "2022-blake3-aes-256-gcm:${ss_pass}" | base64 -w0)
        links="${links}\nss://${ss_ui}@${server_ip}:${ss_port}#SS"
    fi
    
    if [ "$install_trojan" = true ]; then
        [ -n "$inbounds" ] && inbounds="${inbounds},"
        inbounds="${inbounds}{\"type\":\"trojan\",\"tag\":\"trojan\",\"listen\":\"::\",\"listen_port\":${trojan_port},\"users\":[{\"password\":\"${password}\"}],\"tls\":{\"enabled\":true,\"certificate_path\":\"${CERT_DIR}/cert.crt\",\"key_path\":\"${CERT_DIR}/private.key\"}}"
        links="${links}\ntrojan://${password}@${server_ip}:${trojan_port}?sni=${CERT_DOMAIN:-www.bing.com}&allowInsecure=1#Trojan"
    fi
    
    # 生成配置
    echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[{\"type\":\"direct\",\"tag\":\"direct\"}]}" | python3 -m json.tool 2>/dev/null > "$SINGBOX_CONF" || echo "{\"log\":{\"level\":\"info\"},\"inbounds\":[${inbounds}],\"outbounds\":[{\"type\":\"direct\",\"tag\":\"direct\"}]}" > "$SINGBOX_CONF"
    
    echo -e "$links" > "$SINGBOX_DIR/combo_links.txt"
    
    echo -e ""
    echo -e "${Green}========== 预设组合安装完成 ==========${Reset}"
    echo -e ""
    echo -e "${Info} 分享链接:"
    echo -e "${Yellow}$(echo -e "$links")${Reset}"
    echo -e ""
    
    read -p "是否立即启动? [Y/n]: " start_now
    [[ ! $start_now =~ ^[Nn]$ ]] && start_singbox
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
        echo -e " ${Yellow}单协议安装${Reset}"
        echo -e " ${Green}1.${Reset}  Hysteria2 (推荐)"
        echo -e " ${Green}2.${Reset}  TUIC v5"
        echo -e " ${Green}3.${Reset}  VLESS Reality"
        echo -e " ${Green}4.${Reset}  AnyTLS (新)"
        echo -e " ${Green}5.${Reset}  ${Cyan}Any-Reality${Reset} (AnyTLS + Reality)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}多协议组合${Reset}"
        echo -e " ${Green}6.${Reset}  ${Cyan}自定义组合${Reset} (多选协议)"
        echo -e " ${Green}7.${Reset}  ${Cyan}预设组合${Reset} (一键安装)"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Yellow}服务管理${Reset}"
        echo -e " ${Green}8.${Reset}  启动"
        echo -e " ${Green}9.${Reset}  停止"
        echo -e " ${Green}10.${Reset} 重启"
        echo -e " ${Green}11.${Reset} 查看状态"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}12.${Reset} 查看节点信息"
        echo -e " ${Green}13.${Reset} 查看配置文件"
        echo -e " ${Green}14.${Reset} 卸载 sing-box"
        echo -e "${Green}---------------------------------------------------${Reset}"
        echo -e " ${Green}0.${Reset}  返回主菜单"
        echo -e "${Green}========================================================${Reset}"
        
        read -p " 请选择 [0-14]: " choice
        
        case "$choice" in
            1) install_hysteria2 ;;
            2) install_tuic ;;
            3) install_vless_reality ;;
            4) install_anytls ;;
            5) install_any_reality ;;
            6) install_combo ;;
            7) install_preset_combo ;;
            8) start_singbox ;;
            9) stop_singbox ;;
            10) restart_singbox ;;
            11) status_singbox ;;
            12) show_node_info ;;
            13) view_config ;;
            14) uninstall_singbox ;;
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
