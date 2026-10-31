import { UrlLite } from './UrlLite';
import { LocalNetwork } from './LocalNetwork';

/**
 * 主框架域名白名单：名单数据只存在于本地资源文件
 * `entry/src/main/resources/rawfile/domain_whitelist.txt`（已被 .gitignore 排除，
 * 不入库、不随源码分发，但会打进本机构建的 HAP）。文件缺失时白名单为空，
 * 所有 http/https 主框架导航均被拦截。
 *
 * 文件规则（与 Android 版一致）：
 * - 每行一条域名，`#` 开头为注释，空行忽略
 * - `*.a.com` 匹配 a.com 及其任意子域
 * - `a.com` 仅精确匹配该域
 * - 仅约束 http/https 主框架导航；about:、data: 等内部地址不拦
 *
 * 数据加载（rawfile IO）由 app 层注入文本；本类只做纯匹配决策。
 */
export class DomainWhitelist {
  private entries: string[] | null = null;

  /** app 层读取 rawfile 文本后注入（只应调用一次）。 */
  loadFrom(text: string | null): void {
    if (text === null) {
      this.entries = [];
      return;
    }
    this.entries = text
      .split('\n')
      .map((line: string): string => line.trim().toLowerCase())
      .filter((line: string): boolean => line !== '' && !line.startsWith('#'));
  }

  private getEntries(): string[] {
    if (this.entries === null) {
      return [];
    }
    return this.entries;
  }

  /** 名单是否为空（文件缺失或全是注释/空行）——UI 需要据此显式告警。 */
  isEmpty(): boolean {
    return this.getEntries().length === 0;
  }

  /** @return 是否允许访问该 URL 的主框架。 */
  allows(url: string | null): boolean {
    if (url === null || url.trim() === '') {
      return true;
    }
    const parts = UrlLite.parse(url);
    const scheme = parts.scheme;
    if (scheme === null) {
      // 相对地址等无法判定，交浏览器层处理
      return true;
    }
    if (scheme !== 'http' && scheme !== 'https') {
      return true;
    }
    const host = parts.host;
    if (host === null) {
      return false;
    }
    // 内网/本机地址直接放行：白名单是用来挡公网误入的，不该要求把 NAS、路由器、
    // 开发机的 10.x/192.168.x 抄进名单（见 domain/LocalNetwork 的说明）。
    if (LocalNetwork.isLocalHost(host)) {
      return true;
    }
    return this.getEntries().some((entry: string): boolean => DomainWhitelist.matches(host, entry));
  }

  static matches(host: string, entry: string): boolean {
    const e = entry.toLowerCase();
    if (e.startsWith('*.')) {
      const base = e.substring(2);
      return host === base || host.endsWith(`.${base}`);
    }
    return host === e;
  }
}
