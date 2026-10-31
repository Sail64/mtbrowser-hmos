/**
 * 内网地址判定（纯逻辑，零平台依赖）。
 *
 * 用途：白名单只要是"挡公网误入"，就不该拿内网地址去烦用户——内网服务本来就跑在
 * 10./172.16-31./192.168. 这类地址上（自建 NAS、路由器、开发机、容器）。
 * 让用户把这些抄进白名单是多余的仪式，而且会造出"忘了加就整站不可用"的假故障。
 *
 * 覆盖范围：
 * - IPv4 私有段 10/8、172.16/12、192.168/16
 * - IPv4 回环 127/8、链路本地 169.254/16（APIPA / 直连网线）
 * - IPv6 回环 `[::1]`、ULA `fc00::/7`、链路本地 `fe80::/10`（host 带方括号，见 UrlLite）
 * - `localhost`、mDNS `.local`（如 printer.local）
 * - 不含点的单标签主机名（如 `nas`、`router`）——内网 DNS/WINS 里常见的短名
 *
 * 安全说明：这不是放开公网。公网域名、IPv4 公网地址仍然必须命中白名单；
 * 内网可达性本来就由所在网络决定，浏览器白名单不是网络边界。
 */
export class LocalNetwork {
  /** 是否为内网/本机地址（大小写不敏感，允许带 IPv6 方括号）。 */
  static isLocalHost(host: string | null): boolean {
    if (host === null) {
      return false;
    }
    const h = host.trim().toLowerCase();
    if (h === '') {
      return false;
    }
    // IPv6 字面量：[::1] / [fc00::1] / [fe80::1]，可能带端口 [::1]:8080
    if (h.startsWith('[')) {
      const close = h.indexOf(']');
      if (close === -1) {
        return false;
      }
      return LocalNetwork.isLocalV6(h.substring(1, close));
    }
    if (h === 'localhost' || h.endsWith('.local')) {
      return true;
    }
    if (LocalNetwork.isIpv4(h)) {
      return LocalNetwork.isLocalV4(h);
    }
    // 单标签主机名（没有点的短名）：内网里靠 hosts / 内网 DNS 解析
    if (!h.includes('.')) {
      return true;
    }
    // host:port 形式残留（正常不会走到这里，防御性处理）
    const colon = h.indexOf(':');
    if (colon > 0) {
      return LocalNetwork.isLocalHost(h.substring(0, colon));
    }
    return false;
  }

  private static isIpv4(h: string): boolean {
    const seg = h.split('.');
    if (seg.length !== 4) {
      return false;
    }
    for (const s of seg) {
      if (s === '' || !/^\d{1,3}$/.test(s)) {
        return false;
      }
      const n = parseInt(s, 10);
      if (n < 0 || n > 255) {
        return false;
      }
    }
    return true;
  }

  private static isLocalV4(h: string): boolean {
    const seg = h.split('.');
    const a = parseInt(seg[0], 10);
    const b = parseInt(seg[1], 10);
    if (a === 10 || a === 127) {
      return true;
    }
    if (a === 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a === 192 && b === 168) {
      return true;
    }
    if (a === 169 && b === 254) {
      return true;
    }
    return false;
  }

  private static isLocalV6(h: string): boolean {
    if (h === '' ) {
      return false;
    }
    if (h === '::1' || h === '0:0:0:0:0:0:0:1') {
      return true;
    }
    // ULA fc00::/7 → 首字节 fc / fd；链路本地 fe80::/10 → fe8x / fe9x / fea / feb
    const first = h.split(':')[0];
    if (first.length >= 2) {
      const b0 = parseInt(first.substring(0, 2), 16);
      if (b0 >= 0xfc && b0 <= 0xfd) {
        return true;
      }
      if (first === 'fe80' || first === 'fe8' || first === 'fe9' || first === 'fea' || first === 'feb') {
        return true;
      }
    }
    return false;
  }
}