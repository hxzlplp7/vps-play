#!/bin/bash
# VPS-play 一键安装脚本
# 不依赖 git，直接下载

set -e

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"

PROJECT_NAME="vps-play"
INSTALL_DIR="$HOME/$PROJECT_NAME"
REPO_RAW="https://raw.githubusercontent.com/hxzlplp7/vps-play/main"

echo -e "${Cyan}"
cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    通用 VPS 管理工具 - 安装程序
EOF
echo -e "${Reset}"

echo -e "${Green}==================== 开始安装 ====================${Reset}"

# 检查 curl 或 wget
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl -sL"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget -qO-"
else
    echo -e "${Red}[错误]${Reset} 需要 curl 或 wget"
    exit 1
fi

# 创建目录
mkdir -p "$INSTALL_DIR"/{utils,modules/{gost,xui,singbox,frpc,frps,cloudflared,nezha,warp},keepalive,config}

echo -e "${Green}[信息]${Reset} 下载脚本..."

# 下载主要脚本
download_file() {
    local path=$1
    local url="${REPO_RAW}/${path}"
    local dest="${INSTALL_DIR}/${path}"
    
    mkdir -p "$(dirname "$dest")"
    
    if [ "$DOWNLOAD_CMD" = "curl -sL" ]; then
        curl -sL "$url" -o "$dest"
    else
        wget -q "$url" -O "$dest"
    fi
    
    if [ $? -eq 0 ] && [ -s "$dest" ]; then
        chmod +x "$dest" 2>/dev/null || true
        echo -e "  ✓ $path"
    else
        echo -e "  ✗ $path (下载失败)"
    fi
}

# 下载核心文件
echo -e "${Green}[信息]${Reset} 下载核心文件..."
download_file "start.sh"

echo -e "${Green}[信息]${Reset} 下载工具库..."
download_file "utils/env_detect.sh"
download_file "utils/port_manager.sh"
download_file "utils/process_manager.sh"
download_file "utils/network.sh"

echo -e "${Green}[信息]${Reset} 下载功能模块..."
download_file "modules/gost/manager.sh"
download_file "modules/gost/gost.sh"
download_file "modules/xui/manager.sh"
download_file "modules/singbox/manager.sh"
download_file "modules/frpc/manager.sh"
download_file "modules/frps/manager.sh"
download_file "modules/cloudflared/manager.sh"
download_file "modules/nezha/manager.sh"
download_file "modules/warp/manager.sh"

echo -e "${Green}[信息]${Reset} 下载保活模块..."
download_file "keepalive/manager.sh"

# 创建快捷命令
echo -e "${Green}[信息]${Reset} 创建快捷命令..."
mkdir -p "$HOME/bin"

cat > "$HOME/bin/vps-play" << SHORTCUT_EOF
#!/bin/bash
cd "$INSTALL_DIR"
./start.sh "\$@"
SHORTCUT_EOF

chmod +x "$HOME/bin/vps-play"

# 添加到 PATH
add_to_path() {
    local profile_file=$1
    if [ -f "$profile_file" ]; then
        if ! grep -q 'HOME/bin' "$profile_file" 2>/dev/null; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$profile_file"
        fi
    fi
}

add_to_path "$HOME/.profile"
add_to_path "$HOME/.bashrc"
add_to_path "$HOME/.zshrc"

# 使 PATH 立即生效
export PATH="$HOME/bin:$PATH"

echo -e ""
echo -e "${Green}==================== 安装完成 ====================${Reset}"
echo -e ""
echo -e "后续使用方法:"
echo -e "  ${Green}bash ~/vps-play/start.sh${Reset}  - 启动主菜单"
echo -e ""
echo -e "或者重新登录后使用快捷命令:"
echo -e "  ${Green}vps-play${Reset}"
echo -e ""
echo -e "${Green}=================================================${Reset}"
echo -e ""

# 直接运行
echo -e "${Cyan}正在启动 VPS-play...${Reset}"
echo -e ""
cd "$INSTALL_DIR"
exec ./start.sh

