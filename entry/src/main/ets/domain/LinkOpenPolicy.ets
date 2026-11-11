import { UrlLite } from './UrlLite';

/**
 * 「这次导航要不要另开一个标签」的纯决策。
 *
 * ArkWeb 的 onLoadIntercept 对**所有**主框架导航都会回调，包括：
 * 用户点链接、页面脚本自动跳转、302/307 重定向、表单 POST 提交、同页锚点跳转。
 * 只有「用户亲手点的、GET 的、非重定向的、非同页锚点的 http(s) 导航」才该裂成新标签，
 * 其余必须留在原标签，否则会出现：每次重定向都多一个标签、登录表单提交开新标签丢上下文、
 * SPA 自动跳转把标签刷满。
 *
 * 放在 domain：不依赖任何平台 API，可在 Node 里直接断言（tools/smoke-runner.mts）。
 */
export interface LinkNavFacts {
  /** 是否主框架导航（子资源/iframe 一律不裂） */
  isMainFrame: boolean;
  /** 是否由用户手势触发（ArkWeb: WebResourceRequest.isRequestGesture） */
  isRequestGesture: boolean;
  /** 是否重定向（ArkWeb: WebResourceRequest.isRedirect） */
  isRedirect: boolean;
  /** HTTP 方法，大写比较；POST 表单必须留在原标签 */
  method: string;
  /** 目标 URL */
  url: string;
  /** 当前标签正在显示的 URL */
  currentUrl: string;
}

/** 去掉 #fragment，用于判断是否同页锚点 */
function withoutHash(url: string): string {
  const i = url.indexOf('#');
  return i < 0 ? url : url.substring(0, i);
}

/**
 * 是否应当在**新标签**里打开这次导航。
 * 任一条件不满足即返回 false（保守：宁可留在原标签，也不要乱开）。
 */
export function shouldOpenInNewTab(f: LinkNavFacts): boolean {
  if (!f.isMainFrame) {
    return false;
  }
  // 无手势 = 脚本跳转（location.href / meta refresh / 自动重定向）
  if (!f.isRequestGesture) {
    return false;
  }
  // 重定向链留在同一个标签，否则一次 OAuth/302 就能裂出好几个标签
  if (f.isRedirect) {
    return false;
  }
  const method: string = (f.method === undefined || f.method === null) ? 'GET' : f.method.toUpperCase();
  if (method !== 'GET') {
    // 表单 POST：换标签会丢掉提交上下文（验证码、一次性 token 常绑当前文档）
    return false;
  }
  const scheme = UrlLite.schemeOf(f.url);
  if (scheme !== 'http' && scheme !== 'https') {
    // about:blank（内部空白页）、mailto:、javascript: 等都不裂
    return false;
  }
  // 同页锚点（只差 #hash）不裂；currentUrl 为空说明还没有页面，谈不上「当前页」
  const target: string = withoutHash(f.url.trim());
  const current: string = withoutHash((f.currentUrl ?? '').trim());
  if (current !== '' && target === current) {
    return false;
  }
  return true;
}