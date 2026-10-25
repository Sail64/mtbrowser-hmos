/**
 * 纯字符串 URL 解析（无平台依赖，替代 Java URI / @ohos.url 在 domain 的角色）。
 * 只覆盖浏览器导航决策所需：scheme 与小写 host。
 * 已知边界：不做百分号解码、IPv6 字面量按 host 原样返回（白名单场景不涉及）。
 */

/** scheme 规则：RFC 3986，alpha *( ALPHA / DIGIT / "+" / "-" / "." ) */
const SCHEME_RE = /^([a-zA-Z][a-zA-Z0-9+\-.]*):/;

export class UrlParts {
  /** 小写 scheme；无法识别为绝对 URL 时为 null（相对/空串） */
  scheme: string | null;
  /** 小写 host（已去 port、去 userinfo、去尾部根点）；无 host 时为 null */
  host: string | null;

  constructor(scheme: string | null, host: string | null) {
    this.scheme = scheme;
    this.host = host;
  }
}

export class UrlLite {
  static parse(url: string | null): UrlParts {
    if (url === null || url.trim() === '') {
      return new UrlParts(null, null);
    }
    const s = url.trim().replace(/[\t\n\r]/g, '');
    const m = SCHEME_RE.exec(s);
    if (m === null) {
      return new UrlParts(null, null);
    }
    const scheme = m[1].toLowerCase();
    // 仅层次型 URL（scheme://…）有 host。比较时不区分大小写：
    // `HTTPS://a.com` 是合法绝对 URL，按大小写敏感判会把 host 丢成 null（进而被误报「不在白名单」）。
    if (s.substring(0, scheme.length + 3).toLowerCase() !== `${scheme}://`) {
      return new UrlParts(scheme, null);
    }
    let rest = s.substring(scheme.length + 3); // 去掉 "scheme://"
    // authority 终止于 / ? # 和反斜杠。
    // 反斜杠必须算终止符：Chromium 对 http(s) 会把 `\` 规范化为 `/`，所以
    // `https://evil.com\@allowed.com/x` 在浏览器眼里 host 是 evil.com；这里若不认 `\`，
    // lastIndexOf('@') 会取到 allowed.com → 白名单放行一个指向 evil.com 的地址。
    const term = /[\\/?#]/.exec(rest);
    const authority = term === null ? rest : rest.substring(0, term.index);
    // userinfo@host:port → 取最后一个 @
    const at = authority.lastIndexOf('@');
    let hostPort = at === -1 ? authority : authority.substring(at + 1);
    // IPv6 字面量 [::1]:port
    if (hostPort.startsWith('[')) {
      const close = hostPort.indexOf(']');
      if (close !== -1) {
        return new UrlParts(scheme, hostPort.toLowerCase());
      }
      return new UrlParts(scheme, null);
    }
    const colon = hostPort.indexOf(':');
    if (colon !== -1) {
      hostPort = hostPort.substring(0, colon);
    }
    const host = hostPort.toLowerCase().replace(/\.+$/, '');
    return new UrlParts(scheme, host === '' ? null : host);
  }

  /** 便捷：取 scheme（小写），失败返回 null */
  static schemeOf(url: string | null): string | null {
    return UrlLite.parse(url).scheme;
  }

  /** 便捷：取 host（小写），失败返回 null */
  static hostOf(url: string | null): string | null {
    return UrlLite.parse(url).host;
  }

  /**
   * 取站点根：`scheme://host[:port]`，无路径/查询/片段。
   * 用于「恢复上次会话」——恢复深链会撞上后端的未认证深链逻辑（例如 LibreChat 会把
   * 未认证的 /c/xxx 直接踢到 /login 并清会话），等于自己把登录态踢掉一次。
   * 端口必须保留：同一 host 上不同端口是不同服务。
   */
  static originOf(url: string | null): string | null {
    if (url === null) {
      return null;
    }
    const s = url.trim();
    const m = SCHEME_RE.exec(s);
    if (m === null) {
      return null;
    }
    const scheme = m[1].toLowerCase();
    if (s.substring(0, scheme.length + 3).toLowerCase() !== `${scheme}://`) {
      return null;
    }
    const rest = s.substring(scheme.length + 3);
    const term = /[\\/?#]/.exec(rest);
    const authority = term === null ? rest : rest.substring(0, term.index);
    if (authority === '') {
      return null;
    }
    // authority 里去掉 userinfo，保留 host:port
    const at = authority.lastIndexOf('@');
    const hostPort = at === -1 ? authority : authority.substring(at + 1);
    if (hostPort === '') {
      return null;
    }
    return `${scheme}://${hostPort}`;
  }

  /** 是否绝对 URL（带合法 scheme）。 */
  static isAbsolute(url: string): boolean {
    return SCHEME_RE.test(url.trim());
  }

  /**
   * 地址栏输入规范化：无 scheme 一律补 https://（对应 Android 顶栏行为，规则住 domain）。
   */
  static withHttpsPrefix(input: string): string {
    const trimmed = input.trim();
    if (trimmed === '') {
      return '';
    }
    return UrlLite.isAbsolute(trimmed) ? trimmed : `https://${trimmed}`;
  }
}
