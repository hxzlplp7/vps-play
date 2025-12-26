#!/bin/bash
# 改进的 AnyTLS 证书生成脚本
# 包含 IP SAN 支持

# 获取服务器 IP
SERVER_IP=$(curl -s4m5 ip.sb 2>/dev/null || curl -s4m5 ifconfig.me 2>/dev/null)
CERT_DIR="$HOME/.vps-play/singbox/cert"

mkdir -p "$CERT_DIR"

# 创建 OpenSSL 配置文件
cat > "$CERT_DIR/openssl.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = bing.com

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = bing.com
DNS.2 = www.bing.com
IP.1 = ${SERVER_IP}
EOF

# 生成包含 IP SAN 的证书
echo "正在生成包含 IP SAN 的证书..."
echo "服务器 IP: $SERVER_IP"

openssl req -x509 -newkey rsa:2048 \
    -keyout "$CERT_DIR/anytls.key" \
    -out "$CERT_DIR/anytls.crt" \
    -days 36500 -nodes \
    -config "$CERT_DIR/openssl.cnf"

if [ $? -eq 0 ]; then
    echo "✅ 证书生成成功！"
    echo "证书路径: $CERT_DIR/anytls.crt"
    echo "私钥路径: $CERT_DIR/anytls.key"
    echo ""
    echo "证书信息："
    openssl x509 -in "$CERT_DIR/anytls.crt" -noout -text | grep -A 3 "Subject Alternative Name"
    echo ""
    echo "请重启 sing-box 服务使新证书生效"
else
    echo "❌ 证书生成失败"
    exit 1
fi
