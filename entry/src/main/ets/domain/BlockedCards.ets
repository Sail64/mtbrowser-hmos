/**
 * 拦截卡片 + 「文档已被卸载」两个状态，六个入口全走这里。
 *
 * 为什么必须拆成两个状态（历史 bug）：
 * 卡片要显示「被拦的 URL」，落盘却要区分两种拦截：
 * - 提交后拦截（unloaded=true）：文档已被卸成 about:blank，这个标签**没有有效文档**，
 *   落盘必须存空串，否则冷启动会拿一个必然被拒的地址去导航。
 * - 发起时拦截（unloaded=false）：**当前页面还活着**，地址栏和落盘都必须是这个活页面的 URL。
 *   把两者混成一个 Map 的后果是：点一个白名单外的链接，就把正在看的页面持久化成空串，
 *   下次冷启动那个标签变成空白页。
 *
 * 六个入口：block / dismiss / navigate / pageEnd / forget / cardUrlOf
 * 少任何一个，都会出现「卡片不消失」「卡片自己复活」「活页面被写成空串」这类三方不一致。
 */
export class BlockedCards {
  /** tabId → 被拦 URL（只服务界面卡片，不参与落盘决策） */
  private cards: Map<number, string> = new Map<number, string>();
  /** 文档确实已被卸载（只剩下 about:blank）的标签 */
  private unloaded: Set<number> = new Set<number>();

  /** 发生一次拦截。unloaded 表示内核文档是否已被卸载 */
  block(tabId: number, url: string, unloaded: boolean): void {
    this.cards.set(tabId, url);
    if (unloaded) {
      this.unloaded.add(tabId);
    }
  }

  /** 用户主动关掉卡片（「知道了」/ 返回键）。只收起卡片，卸载事实仍然成立 */
  dismiss(tabId: number): void {
    this.cards.delete(tabId);
  }

  /** 该标签开始了**真正成立**的新导航（地址栏提交成功 / 页面自身跳转）：卡片与卸载态都失效 */
  navigate(tabId: number): void {
    this.cards.delete(tabId);
    this.unloaded.delete(tabId);
  }

  /** 页面加载成功（onPageEnd）：同上 */
  pageEnd(tabId: number): void {
    this.navigate(tabId);
  }

  /** 关标签 / 被 LRU 淘汰：全部忘掉，避免 id 复用时串台 */
  forget(tabId: number): void {
    this.cards.delete(tabId);
    this.unloaded.delete(tabId);
  }

  /** 该标签当前应展示的卡片 URL；空串 = 不展示 */
  cardUrlOf(tabId: number): string {
    const u = this.cards.get(tabId);
    return u === undefined ? '' : u;
  }

  /**
   * 落盘用 URL：只有「文档已被卸载」的标签才存空串。
   * 活着的页面（含发起时被拦的）必须原样保留自己的 URL。
   */
  persistedUrlOf(tabId: number, url: string): string {
    return this.unloaded.has(tabId) ? '' : url;
  }

  /** 调试 / 断言用 */
  isUnloaded(tabId: number): boolean {
    return this.unloaded.has(tabId);
  }

  /** 调试 / 断言用 */
  hasCard(tabId: number): boolean {
    return this.cards.has(tabId);
  }
}