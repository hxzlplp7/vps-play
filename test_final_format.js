// 验证最终格式
const node = {
    remark: '剩余流量：99983.38 GB',
    server: '152.53.54.139',
    port: 36001,
    password: '7058fcdd-992a-4761-a8de-8e1b7619962d',
    fingerprint: 'chrome',
    sni: 'hk.zongyunti.site',
    skipCertVerify: true
};

const parts = [
    `name: ${node.remark}`,
    `type: anytls`,
    `server: ${node.server}`,
    `port: ${node.port}`,
    `password: ${node.password}`,
    `client-fingerprint: ${node.fingerprint}`,
    `udp: true`,
    `alpn: [h2, http/1.1]`,
    `sni: ${node.sni}`,
    `skip-cert-verify: ${node.skipCertVerify}`
];

const result = `  - { ${parts.join(', ')} }`;

console.log("✅ 生成的格式:");
console.log(result);

console.log("\n📌 期望的格式:");
console.log("  - { name: '剩余流量：99983.38 GB', type: anytls, server: 152.53.54.139, port: 36001, password: 7058fcdd-992a-4761-a8de-8e1b7619962d, client-fingerprint: chrome, udp: true, alpn: [h2, http/1.1], sni: hk.zongyunti.site, skip-cert-verify: true }");

// 测试 Reality
const realityNode = {
    remark: 'Any-Reality测试',
    server: '1.2.3.4',
    port: 443,
    password: 'test123',
    fingerprint: 'chrome',
    sni: 'apple.com',
    skipCertVerify: true,
    security: 'reality',
    publicKey: 'ABC123',
    shortId: 'def456'
};

const parts2 = [
    `name: ${realityNode.remark}`,
    `type: anytls`,
    `server: ${realityNode.server}`,
    `port: ${realityNode.port}`,
    `password: ${realityNode.password}`,
    `client-fingerprint: ${realityNode.fingerprint}`,
    `udp: true`,
    `alpn: [h2, http/1.1]`,
    `sni: ${realityNode.sni}`,
    `skip-cert-verify: ${realityNode.skipCertVerify}`
];

if (realityNode.security === 'reality' && realityNode.publicKey) {
    let realityParts = [`public-key: ${realityNode.publicKey}`];
    if (realityNode.shortId) {
        realityParts.push(`short-id: ${realityNode.shortId}`);
    }
    parts2.push(`reality-opts: { ${realityParts.join(', ')} }`);
}

const result2 = `  - { ${parts2.join(', ')} }`;

console.log("\n✅ Any-Reality 格式:");
console.log(result2);
