/**
 * 标签模型与生命周期（对应 Android web/TabManager.kt 的纯逻辑部分）。
 *
 * 铁律：本文件零平台依赖——不 import 任何 @ohos.* / @kit.*。
 * 这里只决定「有哪些标签、当前是哪个、超限淘汰谁」；Web 实例的创建/销毁由 UI 层
 * 依据返回的 id 执行（见 ui/BrowserWeb.ets 与 pages/Index.ets）。
 */

/** 空标签页标题（UI 与冒烟断言共用，避免文案漂移）。 */
export const EMPTY_TAB_TITLE: string = '新标签页';

/**
 * 标签上限。
 * Android 用 8（WebView 每实例几十 MB）；ArkWeb 每标签是一个独立渲染实例，内存成本更高，
 * 鸿蒙侧取 4 —— 这是有意的偏离，不是笔误。要改大必须先做真机内存实测。
 */
export const DEFAULT_MAX_TABS: number = 4;

/** 标签元信息：只描述展示所需，不持有 Web 实例。 */
export class TabMeta {
  id: number;
  url: string;
  title: string;
  /** 最近使用时间戳：仅供 LRU 淘汰比较，不影响列表展示顺序。 */
  lastUsedAt: number;
  /** 该标签自己的加载进度（0-100）：切回标签时恢复进度条（Android attachTab 同语义）。 */
  progress: number;

  constructor(id: number, url: string, title: string, lastUsedAt: number, progress: number = 0) {
    this.id = id;
    this.url = url;
    this.title = title;
    this.lastUsedAt = lastUsedAt;
    this.progress = progress;
  }

  /** 概览层主标题：有 title 用 title，否则用 url，再否则「新标签页」。 */
  displayTitle(): string {
    if (this.title !== '') {
      return this.title;
    }
    if (this.url !== '') {
      return this.url;
    }
    return EMPTY_TAB_TITLE;
  }

  /** 概览层副标题。 */
  displayUrl(): string {
    return this.url !== '' ? this.url : '空白页';
  }
}

/** newTab 的结果：新标签 + 因超限被淘汰的标签 id（调用方负责销毁其 Web）。 */
export class NewTabResult {
  tab: TabMeta;
  evicted: number[];
  constructor(tab: TabMeta, evicted: number[]) {
    this.tab = tab;
    this.evicted = evicted;
  }
}

/**
 * 标签列表：打开顺序稳定（概览层不跳动），淘汰依据 lastUsedAt（LRU），
 * current 永不淘汰。
 */
export class TabList {
  private items: TabMeta[] = [];
  private currentTabId: number = -1;
  private nextId: number = 1;
  private maxTabs: number;
  private clock: () => number;

  /**
   * @param maxTabs 上限（ArkWeb 每标签一个渲染实例，内存比 Android WebView 贵，默认 4）
   * @param clock 时间源，注入以便冒烟确定性验证 LRU
   */
  constructor(maxTabs: number = DEFAULT_MAX_TABS, clock: () => number = (): number => Date.now()) {
    this.maxTabs = maxTabs > 0 ? maxTabs : 1;
    this.clock = clock;
  }

  size(): number {
    return this.items.length;
  }

  /** 快照（UI 渲染用；外部修改不影响内部状态）。 */
  all(): TabMeta[] {
    return this.items.slice();
  }

  current(): TabMeta | null {
    return this.find(this.currentTabId);
  }

  currentId(): number {
    return this.currentTabId;
  }

  find(id: number): TabMeta | null {
    for (const it of this.items) {
      if (it.id === id) {
        return it;
      }
    }
    return null;
  }

  /** 新建标签并置为当前；超限时按 LRU 淘汰（排除 current）。 */
  newTab(url: string = '', title: string = ''): NewTabResult {
    const evicted: number[] = [];
    while (this.items.length >= this.maxTabs) {
      const victim = this.lruVictim();
      if (victim === null) {
        break;
      }
      this.remove(victim.id);
      evicted.push(victim.id);
    }
    const tab = new TabMeta(this.nextId, url, title, this.clock());
    this.nextId = this.nextId + 1;
    this.items.push(tab);
    this.currentTabId = tab.id;
    return new NewTabResult(tab, evicted);
  }

  /** 切换当前标签；不存在返回 false。 */
  select(id: number): boolean {
    const tab = this.find(id);
    if (tab === null) {
      return false;
    }
    tab.lastUsedAt = this.clock();
    this.currentTabId = id;
    return true;
  }

  /**
   * 关闭标签，返回关闭后的当前标签 id（全部关完返回 -1）。
   * 选继任者：优先右侧邻居，否则左侧。
   */
  close(id: number): number {
    if (this.find(id) === null) {
      return this.currentTabId;
    }
    const idx = this.indexOf(id);
    this.remove(id);
    if (id !== this.currentTabId) {
      return this.currentTabId;
    }
    if (this.items.length === 0) {
      this.currentTabId = -1;
    } else {
      const next = idx < this.items.length ? this.items[idx] : this.items[this.items.length - 1];
      this.currentTabId = next.id;
      next.lastUsedAt = this.clock();
    }
    return this.currentTabId;
  }

  /** 关闭除 id 之外的标签，返回被关闭的 id 列表（供 UI 销毁 Web）。 */
  closeOthers(id: number): number[] {
    const closed: number[] = [];
    for (const it of this.items.slice()) {
      if (it.id !== id) {
        closed.push(it.id);
        this.remove(it.id);
      }
    }
    if (this.find(id) !== null) {
      this.currentTabId = id;
      const tab = this.find(id);
      if (tab !== null) {
        tab.lastUsedAt = this.clock();
      }
    }
    return closed;
  }

  /** 页面导航完成：更新 url（标题走 rename，避免「非空才写」把页面的清空操作吃掉）。 */
  update(id: number, url: string): void {
    const tab = this.find(id);
    if (tab === null) {
      return;
    }
    if (url !== '') {
      tab.url = url;
    }
  }

  /** 标题同步：无条件覆盖（页面可以把 title 清空，Android 同语义）。 */
  rename(id: number, title: string): void {
    const tab = this.find(id);
    if (tab !== null) {
      tab.title = title;
    }
  }

  /** 记录某标签自己的加载进度，供切换标签时恢复进度条。 */
  setProgress(id: number, progress: number): void {
    const tab = this.find(id);
    if (tab !== null) {
      tab.progress = progress;
    }
  }

  progressOf(id: number): number {
    const tab = this.find(id);
    return tab !== null ? tab.progress : 0;
  }

  private lruVictim(): TabMeta | null {
    let victim: TabMeta | null = null;
    for (const it of this.items) {
      if (it.id === this.currentTabId) {
        continue;
      }
      if (victim === null || it.lastUsedAt < victim.lastUsedAt) {
        victim = it;
      }
    }
    return victim;
  }

  private indexOf(id: number): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private remove(id: number): void {
    const idx = this.indexOf(id);
    if (idx >= 0) {
      this.items.splice(idx, 1);
    }
  }
}