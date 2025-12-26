// AnyTLS Worker.js 改进测试脚本
// 用于验证 parseAnyTLSLink 和 anyTLSToClashYAML 函数

// 复制改进后的函数
function parseAnyTLSLink(link) {
    try {
        const url = new URL(link);

        const server = url.hostname;
        const port = parseInt(url.port) || 443;
        const password = decodeURIComponent(url.username);
        const remark = url.hash ? decodeURIComponent(url.hash.substring(1)) : `AnyTLS-${server}`;

        const params = new URLSearchParams(url.search);
        const insecure = params.get('insecure') === '1' || params.get('allowInsecure') === '1' || !params.has('insecure');
        const sni = params.get('sni') || server;
        const fingerprint = params.get('fp') || 'chrome';
        const security = params.get('security') || '';

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
            publicKey,
            shortId,
            raw: link
        };
    } catch (e) {
        console.error('解析 AnyTLS 链接失败:', e, '链接:', link);

        try {
            const match = link.match(/^anytls:\/\/([^@]+)@([^:]+):(\d+)(?:#(.+))?$/);
            if (!match) return null;

            const [, password, server, port, remark] = match;
            return {
                password: decodeURIComponent(password),
                server,
                port: parseInt(port),
                remark: remark ? decodeURIComponent(remark) : `AnyTLS-${server}`,
                skipCertVerify: true,
                sni: server,
                fingerprint: 'chrome',
                security: '',
                publicKey: '',
                shortId: '',
                raw: link
            };
        } catch (e2) {
            console.error('简单解析也失败:', e2);
            return null;
        }
    }
}

function anyTLSToClashYAML(node) {
    let yaml = `  - name: "${node.remark}"
    type: anytls
    server: ${node.server}
    port: ${node.port}
    password: "${node.password}"
    skip-cert-verify: ${node.skipCertVerify}
    sni: "${node.sni}"
    client-fingerprint: ${node.fingerprint}
    udp: true`;

    yaml += `\n    alpn:
      - h2
      - http/1.1`;

    if (node.security === 'reality' && node.publicKey) {
        yaml += `\n    reality-opts:
      public-key: ${node.publicKey}`;
        if (node.shortId) {
            yaml += `\n      short-id: ${node.shortId}`;
        }
    }

    return yaml;
}

// 测试用例
const testCases = [
    {
        name: '基础 AnyTLS（完整参数）',
        link: 'anytls://MyPassword123@168.231.97.89:443?insecure=1&sni=bing.com&fp=chrome#AnyTLS-Test'
    },
    {
        name: 'Any-Reality（完整配置）',
        link: 'anytls://SecretPass@1.2.3.4:443?security=reality&sni=apple.com&fp=chrome&pbk=ABCDEFGHIJKLMN&sid=1234abcd#Any-Reality-Node'
    },
    {
        name: '简化格式（向后兼容）',
        link: 'anytls://password@example.com:8443#SimpleNode'
    },
    {
        name: '无端口（默认443）',
        link: 'anytls://pass@host.com#NoPort'
    },
    {
        name: 'allowInsecure别名',
        link: 'anytls://test@test.com:443?allowInsecure=1&sni=google.com#AllowInsecure'
    },
    {
        name: 'VPS-play标准格式',
        link: 'anytls://Abc123456789@168.231.97.89:443?insecure=1&allowInsecure=1#anytls-vps'
    }
];

// 运行测试
console.log('========== AnyTLS Worker.js 改进测试 ==========\n');

testCases.forEach((testCase, index) => {
    console.log(`\n测试 ${index + 1}: ${testCase.name}`);
    console.log('━'.repeat(60));
    console.log(`输入: ${testCase.link}`);

    const node = parseAnyTLSLink(testCase.link);
    if (node) {
        console.log('\n✅ 解析成功:');
        console.log(JSON.stringify(node, null, 2));

        console.log('\n📄 Clash YAML:');
        const yaml = anyTLSToClashYAML(node);
        console.log(yaml);
    } else {
        console.log('\n❌ 解析失败');
    }
    console.log('');
});

console.log('\n========== 测试完成 ==========');

// Node.js 环境下运行
if (typeof module !== 'undefined' && module.exports) {
    // 导出函数供外部测试
    module.exports = {
        parseAnyTLSLink,
        anyTLSToClashYAML
    };
}
