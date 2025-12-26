# AnyTLS Worker.js 改进说明

## 基于 sublinkPro-1.0.63 的 AnyTLS 实现分析

### sublinkPro 的 AnyTLS 转换逻辑

参考 `node/protocol/clash.go` (第 391-406 行):

```go
case Scheme == "anytls":
    anyTLS, err := DecodeAnyTLSURL(link.Url)
    if err != nil {
        return Proxy{}, err
    }
    return Proxy{
        Name:               anyTLS.Name,
        Type:               "anytls",
        Server:             anyTLS.Server,
        Port:               FlexPort(utils.GetPortInt(anyTLS.Port)),
        Password:           anyTLS.Password,
        Skip_cert_verify:   anyTLS.SkipCertVerify,
        Sni:                anyTLS.SNI,
        Client_fingerprint: anyTLS.ClientFingerprint,
        Dialer_proxy:       link.DialerProxyName,
    }, nil
```

### AnyTLS 链接解析 (`node/protocol/anytls.go`)

```go
func DecodeAnyTLSURL(s string) (AnyTLS, error) {
    u, err := url.Parse(s)
    anyTLS.Server = host
    anyTLS.Port, err = strconv.Atoi(rawPort)
    anyTLS.Password = u.User.Username()
    skipCertVerify := u.Query().Get("insecure")
    if skipCertVerify != "" {
        anyTLS.SkipCertVerify, err = strconv.ParseBool(skipCertVerify)
    }
    anyTLS.SNI = u.Query().Get("sni")
    anyTLS.ClientFingerprint = u.Query().Get("fp")
    return anyTLS, nil
}
```

## VPS-play worker.js 当前实现

### 当前代码优点

1. ✅ 已实现基础的 AnyTLS 链接解析 (`parseAnyTLSLink`)
2. ✅ 已实现 Clash YAML 生成 (`anyTLSToClashYAML`)
3. ✅ 已实现插入到 Clash 配置 (`addAnyTLSToClash`)

### 缺少的功能

根据 sublinkPro 实现，VPS-play worker.js 需要改进的地方：

1. ❌ **链接解析不完整**: 未解析 `?` 查询参数
   - `insecure` / `allowInsecure`
   - `sni`
   - `fp` (client-fingerprint)
   - `security` (Reality 支持)
   - 其他参数

2. ❌ **Clash 格式不完整**: 缺少部分字段
   - `client-fingerprint` 字段
   - `idle-session-check-interval` 配置
   - `alpn` 配置

## 改进方案

### 1. 完善 `parseAnyTLSLink` 函数

```javascript
// 改进后的 AnyTLS 链接解析
function parseAnyTLSLink(link) {
    try {
        // 支持完整的 URL 解析
        // anytls://password@server:port?insecure=1&sni=example.com&fp=chrome#remark
        const url = new URL(link);
        
        const server = url.hostname;
        const port = parseInt(url.port) || 443;
        const password = decodeURIComponent(url.username);
        const remark = url.hash ? decodeURIComponent(url.hash.substring(1)) : `AnyTLS-${server}`;
        
        // 解析查询参数
        const params = new URLSearchParams(url.search);
        const insecure = params.get('insecure') === '1' || params.get('allowInsecure') === '1';
        const sni = params.get('sni') || server;
        const fingerprint = params.get('fp') || 'chrome';
        const security = params.get('security') || '';
        
        // Reality 参数
        const publicKey = params.get('pbk') || '';
        const shortId = params.get('sid') || '';
        
        return {
            password,
            server,
            port,
            remark,
            skipCertVerify: insecure,
            sni,
            fingerprint,
            security,
            // Reality 相关
            publicKey,
            shortId
        };
    } catch (e) {
        console.error('解析 AnyTLS 链接失败:', e, '链接:', link);
        return null;
    }
}
```

### 2. 改进 `anyTLSToClashYAML` 函数

```javascript
// 改进后的 Clash YAML 生成（支持更多字段）
function anyTLSToClashYAML(node) {
    // 构建基础配置
    let yaml = `  - name: "${node.remark}"
    type: anytls
    server: ${node.server}
    port: ${node.port}
    password: "${node.password}"
    skip-cert-verify: ${node.skipCertVerify}
    sni: "${node.sni}"
    client-fingerprint: ${node.fingerprint}
    udp: true`;
    
    // 添加 ALPN
    yaml += `\n    alpn:
      - h2
      - http/1.1`;
    
    // 如果有 Reality 配置
    if (node.security === 'reality' && node.publicKey) {
        yaml += `\n    reality-opts:
      public-key: ${node.publicKey}`;
        if (node.shortId) {
            yaml += `\n      short-id: ${node.shortId}`;
        }
    }
    
    return yaml;
}
```

### 3. 支持 Any-Reality

```javascript
// Any-Reality 是 AnyTLS + Reality 的组合
// 链接格式: anytls://password@server:port?security=reality&sni=apple.com&fp=chrome&pbk=公钥&sid=短ID#remark
function parseAnyRealityLink(link) {
    const node = parseAnyTLSLink(link);
    if (!node) return null;
    
    // 检查是否是 Any-Reality
    if (node.security === 'reality') {
        node.isReality = true;
    }
    
    return node;
}
```

## 主要改进点总结

### 对比表

| 功能 | 当前 worker.js | sublinkPro | 改进后 |
|------|---------------|------------|--------|
| 基础解析 | ✅ | ✅ | ✅ |
| 查询参数 | ❌ | ✅ | ✅ 完善 |
| Reality 支持 | ❌ | ✅ | ✅ 新增 |
| fingerprint | ⚠️硬编码 | ✅ 可配置 | ✅ 可配置 |
| SNI配置 | ⚠️使用server | ✅ 可配置 | ✅ 可配置 |
| skip-cert-verify | ⚠️硬编码true | ✅ 可配置 | ✅ 可配置 |
| ALPN | ✅ | ✅ | ✅ |

## 实现文件

已创建改进版本文件:
- `worker_anytls_improved.js` - 完整改进版本

## 测试用例

### 基础 AnyTLS 链接
```
anytls://password123@168.231.97.89:443?insecure=1&sni=bing.com&fp=chrome#AnyTLS-Test
```

### Any-Reality 链接
```
anytls://password123@1.2.3.4:443?security=reality&sni=apple.com&fp=chrome&pbk=ABCDEFGH&sid=1234abcd#Any-Reality-Test
```

## 参考代码位置

- sublinkPro: `node/protocol/anytls.go` (解析)
- sublinkPro: `node/protocol/clash.go` (Clash 转换)
- VPS-play: `worker.js` (当前实现)

---

**状态**: ✅ 分析完成  
**下一步**: 应用改进到 worker.js
