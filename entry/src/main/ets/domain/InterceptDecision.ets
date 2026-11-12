import { NavigationDecision } from './model/CertModels';
import type { LinkNavFacts } from './LinkOpenPolicy';
import { shouldOpenInNewTab } from './LinkOpenPolicy';

/**
 * `onLoadIntercept` 的判定结果。顺序本身是安全语义的一部分，所以必须可断言：
 * 先 scheme 闸门 → 再白名单 → 最后才谈「裂标签」。
 */
export enum InterceptAction {
  /** 放行，当前标签内加载 */
  LOAD = 0,
  /** 另开标签（本次导航取消） */
  NEW_TAB = 1,
  /** 交给系统应用（mailto/tel/sms/geo） */
  OPEN_EXTERNAL = 2,
  /** 危险 scheme，不外抛也不加载 */
  BLOCK_SCHEME = 3,
  /** 主框架目标不在白名单，发起时拦截 */
  BLOCK_WHITELIST = 4
}

/**
 * 拦截决策（纯函数）。
 *
 * 顺序不能换：
 * 1. 危险 scheme 先挡 —— 它连白名单都不该参与判断；
 * 2. 白名单在裂标签**之前** —— 被拦的链接不该先裂出一个新标签再在新标签里被拦
 *    （那会变成「新标签 + 另一张拦截卡片」两个坑）；
 * 3. 只有确认可访问，才考虑「这次点击要不要新开标签」。
 */
export function decideIntercept(
  nav: NavigationDecision,
  whitelistAllows: boolean,
  facts: LinkNavFacts
): InterceptAction {
  if (nav === NavigationDecision.OPEN_EXTERNAL) {
    return InterceptAction.OPEN_EXTERNAL;
  }
  if (nav === NavigationDecision.BLOCK) {
    return InterceptAction.BLOCK_SCHEME;
  }
  if (facts.isMainFrame && !whitelistAllows) {
    return InterceptAction.BLOCK_WHITELIST;
  }
  if (shouldOpenInNewTab(facts)) {
    return InterceptAction.NEW_TAB;
  }
  return InterceptAction.LOAD;
}