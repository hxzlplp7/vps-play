#!/bin/bash
# VPS-play 一键安装脚本

set -e

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Cyan="\033[36m"
Reset="\033[0m"

PROJECT_NAME="VPS-play"
INSTALL_DIR="$HOME/$PROJECT_NAME"
REPO_URL="https://github.com/hxzlplp7/vps-play.git"

echo -e "${Cyan}"
cat << "EOF"
    ╦  ╦╔═╗╔═╗   ╔═╗╦  ╔═╗╦ ╦
    ╚╗╔╝╠═╝╚═╗───╠═╝║  ╠═╣╚╦╝
     ╚╝ ╩  ╚═╝   ╩  ╩═╝╩ ╩ ╩ 
    通用 VPS 管理工具 - 安装程序
EOF
echo -e "${Reset}"

echo -e "${Green}==================== 开始安装 ====================${Reset}"

# 检查 git
if ! command -v git &>/dev/null; then
    echo -e "${Red}[错误]${Reset} 未找到 git，正在安装..."
    
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y git
    elif command -v yum &>/dev/null; then
        sudo yum install -y git
    elif command -v pkg &>/dev/null; then
        pkg install -y git
    else
        echo -e "${Red}[错误]${Reset} 无法自动安装 git，请手动安装"
        exit 1
    fi
fi

# 删除旧版本
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${Yellow}[警告]${Reset} 检测到旧版本，正在备份..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
fi

# 克隆仓库
echo -e "${Green}[信息]${Reset} 正在下载 $PROJECT_NAME..."
git clone "$REPO_URL" "$INSTALL_DIR"

# 进入目录
cd "$INSTALL_DIR"

# 设置权限
chmod +x start.sh
chmod +x utils/*.sh 2>/dev/null || true

# 创建快捷命令
echo -e "${Green}[信息]${Reset} 创建快捷命令..."
mkdir -p "$HOME/bin"

cat > "$HOME/bin/vps-play" << 'SHORTCUT_EOF'
#!/bin/bash
cd "$HOME/VPS-play"
./start.sh "$@"
SHORTCUT_EOF

chmod +x "$HOME/bin/vps-play"

# 添加到 PATH
if ! grep -q 'HOME/bin' "$HOME/.profile" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.profile"
fi

if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo -e ""
echo -e "${Green}==================== 安装完成 ====================${Reset}"
echo -e "${Cyan}快捷命令已创建！${Reset}"
echo -e ""
echo -e "使用方法:"
echo -e "  ${Green}vps-play${Reset}          - 启动主菜单"
echo -e "  ${Green}cd ~/VPS-play${Reset}     - 进入安装目录"
echo -e "  ${Green}./start.sh${Reset}        - 直接运行主脚本"
echo -e ""
echo -e "请运行以下命令使快捷命令生效:"
echo -e "  ${Yellow}source ~/.profile${Reset}"
echo -e ""
echo -e "或者重新登录 Shell"
echo -e "${Green}=================================================${Reset}"
echo -e ""

# 询问是否立即运行
read -p "是否立即启动 VPS-play? [Y/n]: " run_now
run_now=${run_now:-Y}

if [[ $run_now =~ ^[Yy]$ ]]; then
    ./start.sh
fi
