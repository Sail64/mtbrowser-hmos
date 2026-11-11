import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppGraph } from '../app/AppGraph';
import { UrlLite } from '../domain/UrlLite';
import { Site } from '../domain/model/Site';
import { TabList, TabMeta, NewTabResult, DEFAULT_MAX_TABS } from '../domain/TabList';
import { SaveOutcome } from '../domain/BookmarkService';
import { CertReminderNotifier } from '../domain/ServerCertReminderService';
import { HomeView } from '../ui/HomeView';
import { BrowserWeb } from '../ui/BrowserWeb';
import { TabSwitcher } from '../ui/TabSwitcher';
import { SiteEditorDialog } from '../ui/SiteEditorDialog';
import { ToastNotifier } from '../ui/ToastNotifier';
import { FullscreenFab } from '../ui/FullscreenFab';

/** 首次导航重试：6 次 × 120ms ≈ 720ms 内 Web 仍未 attach 才判失败 */
const OPEN_RETRY_LEFT: number = 6;
const OPEN_RETRY_INTERVAL_MS: number = 120;

/**
 * 薄控制器（对应 Android MainActivity.kt）：标签管理、主页/浏览切换、返回键、地址栏状态。
 * 铁律：这里只允许「视图切换 + 状态转发」，标签规则全部在 domain/TabList。
 *
 * 渲染策略：Web 组件常驻（Stack + visibility），切换标签不销毁实例，
 * 滚动位置 / JS 状态 / 表单内容全部保留——与 Android 的「每标签独立 WebView」等价。
 */
@Entry
@Component
struct Index {
  /** 标签 id 列表（只存 id，保证 ForEach 组件身份稳定，不因标题变化重建 Web） */
  @State tabIds: number[] = [];
  @State currentId: number = -1;
  /** 元信息版本号：标题/URL 变化时递增，驱动顶栏与概览层刷新 */
  @State metaVersion: number = 0;
  @State showHome: boolean = true;
  @State homeOverlay: boolean = false;
  @State switcherVisible: boolean = false;
  @State progress: number = 0;
  @State address: string = '';
  /** 用户正在编辑地址栏时不要被页面导航覆盖 */
  @State addressEditing: boolean = false;
  @State starred: boolean = false;
  @State homeTick: number = 0;
  /** 全屏（沉浸）模式：只隐藏应用顶部操作栏，系统栏不动（与 Android ImmersiveController 同语义） */
  @State fullscreen: boolean = false;
  /** Web 区域尺寸：给悬浮按钮做边界钳制 */
  @State webW: number = 0;
  @State webH: number = 0;
  /** 当前标签要展示的拦截地址（空 = 不展示卡片）。URL 必须留在界面上让用户能复制走。 */
  @State blockedUrl: string = '';
  /**
   * 按标签记住被拦地址（tabId → url），**只在内存里**，绝不落盘：
   * 落盘的话冷启动恢复会拿一个必然再被拦的地址去导航，还会把用户上次真正在看的页面顶掉。
   * 切回该标签时靠它把卡片重新挂上，避免「地址栏有 URL、页面空白、卡片却没了」。
   */
  private blockedByTab: Map<number, string> = new Map<number, string>();
  /** 本轮是否已经"退回主页覆盖层"过一次（用于让返回键有终点，不再死循环） */
  private backHomeOnce: boolean = false;
  /** persistTabs 节流时间戳（pageEnd 可能很密集，不必每次都写 preferences） */
  private lastPersistAt: number = 0;

  private tabList: TabList = new TabList(DEFAULT_MAX_TABS);
  private controllers: Map<number, webview.WebviewController> = new Map();
  private editorCtrl: CustomDialogController | null = null;
  /** 统一 toast 出口（与 BrowserWeb 用同一个实现，避免两套提示风格） */
  private notifier: CertReminderNotifier | null = null;

  aboutToAppear(): void {
    this.notifier = new ToastNotifier(this.getUIContext().getPromptAction());
    // 内核下载委托全局注册一次（下载走内核栈才继承 mTLS/证书豁免）
    AppGraph.installDownloader(this.notifier);
    // 恢复上次的会话：把所有还开着的标签一起恢复，而不是退回单一首页
    // （用户抱怨过"冷启动总是跳回固定站点"）。
    const savedTabs = AppGraph.settings().getOpenTabs();
    // 全是空标签（用户把标签都清空了）时不该恢复成"4 个空白页且回不到主页"，
    // 直接走下面的旧逻辑（多半也没有 lastUrl，最终停在主页）。
    let hasAnyUrl = false;
    for (const u of savedTabs) {
      if (u !== '') {
        hasAnyUrl = true;
        break;
      }
    }
    if (savedTabs.length > 0 && hasAnyUrl) {
      const wl = AppGraph.domainWhitelist();
      const seen: string[] = [];
      let restoredAny = false;
      for (const u of savedTabs) {
        if (u === '') {
          const blank = this.tabList.newTab('');
          this.dropEvicted(blank.evicted);
          restoredAny = true;
          continue;
        }
        if (!wl.allows(u) || !Index.isRestorableUrl(u)) {
          continue;
        }
        // 只恢复站点根，不恢复深链：未认证深链会让后端把人踢到登录页并清会话
        // （LibreChat 的 /c/xxx 就是这种），那样每启动一次就注销一次。
        const origin = UrlLite.originOf(u);
        if (origin === null || seen.indexOf(origin) >= 0) {
          continue;
        }
        seen.push(origin);
        const created: NewTabResult = this.tabList.newTab(origin);
        this.dropEvicted(created.evicted);
        restoredAny = true;
      }
      if (restoredAny) {
        const all = this.tabList.all();
        const want = AppGraph.settings().getOpenTabsCurrent();
        let idx = want >= 0 && want < all.length ? want : all.length - 1;
        // 存下来的当前标签可能是空白页（比如上次是新建标签后被划掉）：
        // 优先切到第一个有地址的标签，别让用户一进来就对着白屏。
        if (all[idx].url === '') {
          for (let i = 0; i < all.length; i++) {
            if (all[i].url !== '') {
              idx = i;
              break;
            }
          }
        }
        this.tabList.select(all[idx].id);
        this.showHome = false;
        this.homeOverlay = false;
        this.syncTabs();
        // 启动时打一行 cookie 计数：和 pageEnd 那行对照，就能判断是"没写盘"还是"没读回"
        AppGraph.reportCookies(all[idx].url, 'startup');
        return;
      }
    }
    // 没有会话记录时才退回 Android 的旧语义：lastUrl 的 host 命中书签才自动恢复站点根
    const last = AppGraph.settings().getLastUrl();
    if (last === null || last === '') {
      return;
    }
    const host = UrlLite.hostOf(last);
    if (host === null) {
      return;
    }
    const site = AppGraph.siteRepository().byHost(host);
    if (site === null) {
      return;
    }
    this.openUrl(site.url, false);
  }

  // ---------- 标签基础设施 ----------

  private controllerOf(id: number): webview.WebviewController {
    let c = this.controllers.get(id);
    if (c === undefined) {
      c = new webview.WebviewController();
      this.controllers.set(id, c);
    }
    return c;
  }

  /** TabList（纯逻辑）→ UI 状态同步。 */
  private syncTabs(): void {
    this.tabIds = this.tabList.all().map((t: TabMeta): number => t.id);
    this.currentId = this.tabList.currentId();
    this.metaVersion = this.metaVersion + 1;
    this.syncAddress();
    this.persistTabs();
  }

  /** 节流版写盘：pageEnd / blocked 这类高频事件走它，1.5s 内最多写一次。 */
  private persistTabsThrottled(): void {
    if (Date.now() - this.lastPersistAt < 1500) {
      return;
    }
    this.persistTabs();
  }

  /** 只有 http/https 的 URL 才允许从偏好里恢复（与 openUrl 的 scheme 闸门同一条规则）。 */
  private static isRestorableUrl(url: string): boolean {
    const scheme = UrlLite.schemeOf(url);
    return scheme === 'http' || scheme === 'https';
  }

  /** 把当前标签集合写盘，供下次冷启动恢复（被杀掉也不丢会话）。 */
  private persistTabs(): void {
    this.lastPersistAt = Date.now();
    const all = this.tabList.all();
    if (all.length === 0) {
      AppGraph.settings().setOpenTabs([], 0);
      return;
    }
    // 被拦标签存空串：它当下没有有效文档，存被拦 URL 只会让下次恢复把一个必然被拒的地址
    // 再导航一遍（或整标签被白名单过滤掉，把用户真正在看的页面顶掉）。
    const urls: string[] = all.map((t: TabMeta): string => this.blockedByTab.has(t.id) ? '' : t.url);
    let idx = 0;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === this.tabList.currentId()) {
        idx = i;
      }
    }
    AppGraph.settings().setOpenTabs(urls, idx);
  }

  private dropEvicted(evicted: number[]): void {
    for (const id of evicted) {
      this.controllers.delete(id);
      this.blockedByTab.delete(id);
    }
  }

  private syncAddress(): void {
    const tab = this.tabList.current();
    // 用户正在输入时不得用页面 URL 覆盖地址栏（Android 用独立输入对话框天然隔离）
    if (!this.addressEditing) {
      this.address = tab !== null ? tab.url : '';
    }
    this.updateStar();
  }

  private updateStar(): void {
    const tab = this.tabList.current();
    this.starred = tab !== null && tab.url !== '' &&
      AppGraph.siteRepository().findByUrl(tab.url) !== null;
  }

  // ---------- 导航 ----------

  /**
   * 打开地址。
   * @param reuseCurrent true = 在当前标签加载（书签点击/地址栏提交）；false = 新开标签
   */
  private openUrl(raw: string, reuseCurrent: boolean): void {
    this.blockedUrl = '';
    if (this.currentId >= 0) {
      this.blockedByTab.delete(this.currentId);
    }
    const url = UrlLite.withHttpsPrefix(raw);
    if (url === '') {
      return;
    }
    // 只接受 http/https：loadUrl('javascript:...') 会在当前页上下文执行，
    // 而 DomainWhitelist 对非 http(s) 是放行的（它只负责"该域是否允许"，不负责 scheme 安全）。
    const scheme = UrlLite.schemeOf(url);
    if (scheme !== 'http' && scheme !== 'https') {
      this.toast('只支持 http/https 地址');
      return;
    }
    // 前置白名单检查：UI 入口先拦，不发起任何网络（与 Android loadIfAllowed 一致）
    if (!AppGraph.domainWhitelist().allows(url)) {
      this.toast('该域名不在允许访问的白名单内');
      return;
    }
    // last_url 只在页面真正加载完成时写（onTabPageEnd），
    // 否则加载失败/被白名单兜底卸载的地址也会被记成「上次访问」，下次冷启动恢复成打不开的页。
    const hasCurrent = reuseCurrent && this.tabList.currentId() >= 0;
    if (hasCurrent) {
      const id = this.tabList.currentId();
      // Web 未 attach 时 loadUrl 会抛（新建标签立刻点书签的场景）。
      // 不靠单次定时碰运气：有界重试，全部失败才提示，别把用户操作吞掉。
      this.loadWithRetry(id, url, OPEN_RETRY_LEFT);
    } else {
      const created: NewTabResult = this.tabList.newTab(url);
      this.dropEvicted(created.evicted);
    }
    // 导航后返回键回到"网页后退优先"的原点
    this.backHomeOnce = false;
    const target = this.tabList.currentId();
    if (target >= 0) {
      this.tabList.setProgress(target, 0); // 上一次被 abort 的加载进度不得残留
    }
    this.showHome = false;
    this.homeOverlay = false;
    this.switcherVisible = false;
    this.progress = 0;
    this.syncTabs();
  }

  /**
   * 在指定标签加载 URL，Web 未 attach 时 index 抛错 → 有界重试。
   * 重试耗尽才提示，避免「刚建标签就点书签」被一次 80ms 的运气决定成败。
   */
  private loadWithRetry(tabId: number, url: string, left: number): void {
    try {
      this.controllerOf(tabId).loadUrl(url);
      return;
    } catch (e) {
      if (left <= 0) {
        hilog.error(0x0001, 'Index', 'loadUrl gave up after retries: %{public}s', JSON.stringify(e));
        this.toast('页面暂时无法加载，请稍后重试');
        return;
      }
    }
    setTimeout(() => {
      this.loadWithRetry(tabId, url, left - 1);
    }, OPEN_RETRY_INTERVAL_MS);
  }

  private newTab(): void {
    this.blockedUrl = '';
    const created: NewTabResult = this.tabList.newTab('');
    this.dropEvicted(created.evicted);
    this.switcherVisible = false;
    // 新标签先引导到书签选择（与 Android 一致：空白页 + 主页覆盖层）
    this.showHome = true;
    this.homeOverlay = true;
    this.homeTick = this.homeTick + 1;
    this.syncTabs();
  }

  private selectTab(id: number): void {
    if (this.tabList.select(id)) {
      this.switcherVisible = false;
      this.backHomeOnce = false;
      this.showHome = false;
      this.homeOverlay = false;
      // 首次导航由 BrowserWeb 自己在 active 变 true 时补上（隐藏状态下控制器没就绪，
      // 父层隔空 loadUrl 会静默失败 → 切过去永远白屏）。
      // 被拦过又没重新加载的标签：卡片要跟着回来，否则地址栏有 URL、页面空白、卡片没了
      this.blockedUrl = this.blockedByTab.get(id) ?? '';
      // 恢复该标签自己的进度（它可能仍在加载）
      this.progress = this.tabList.progressOf(id);
      this.syncTabs();
    }
  }

  private closeTab(id: number): void {
    // 只有关掉的是当前标签才重置进度条，否则会把别的标签正在走的进度掐掉
    const wasCurrent = id === this.tabList.currentId();
    const remaining = this.tabList.close(id);
    this.controllers.delete(id);
    this.blockedByTab.delete(id);
    if (wasCurrent) {
      this.progress = remaining < 0 ? 0 : this.tabList.progressOf(remaining);
      // 当前标签被关掉后，卡片要跟着新的当前标签走（关掉的正好是被拦标签时卡片必须消失）
      this.blockedUrl = remaining < 0 ? '' : (this.blockedByTab.get(remaining) ?? '');
    }
    if (remaining < 0) {
      this.showHome = true;
      this.homeOverlay = false;
      this.switcherVisible = false;
    }
    this.syncTabs();
  }

  private closeOthers(id: number): void {
    const closed = this.tabList.closeOthers(id);
    for (const cid of closed) {
      this.controllers.delete(cid);
      this.blockedByTab.delete(cid);
    }
    this.blockedUrl = this.blockedByTab.get(id) ?? '';
    this.showHome = false;
    this.switcherVisible = false;
    this.toast('已关闭其他标签');
    this.syncTabs();
  }

  // ---------- 主页/浏览切换 ----------

  private showHomeLayer(): void {
    this.blockedUrl = '';
    this.fullscreen = false;
    this.showHome = true;
    // 有会话 → 覆盖层（✕/返回回原页面）；无会话 → 独立主页（返回退出应用）
    this.homeOverlay = this.tabList.size() > 0;
    this.homeTick = this.homeTick + 1;
  }

  private closeHomeOverlay(): void {
    if (this.tabList.size() === 0) {
      return;
    }
    this.showHome = false;
    this.homeOverlay = false;
    // 回主页时卡片收起（showHomeLayer 清过），回到浏览态必须按当前标签重新挂上，
    // 否则又是一屏「地址栏有被拦 URL、页面空白、卡片没有」。
    this.blockedUrl = this.blockedByTab.get(this.tabList.currentId()) ?? '';
  }

  private removeSite(site: Site): void {
    AppGraph.siteRepository().remove(site.id);
    this.toast('已删除');
    this.homeTick = this.homeTick + 1;
  }

  // ---------- 收藏 ----------

  private bookmarkCurrent(): void {
    const tab = this.tabList.current();
    if (tab === null || tab.url === '') {
      this.toast('当前没有可收藏的页面');
      return;
    }
    const existing = AppGraph.siteRepository().findByUrl(tab.url);
    if (existing !== null) {
      // 已收藏 → 打开编辑（与 Android 一致）
      this.showEditor(existing, existing.name, existing.url, '编辑站点');
    } else {
      const host = UrlLite.hostOf(tab.url) ?? '';
      this.showEditor(null, tab.title !== '' ? tab.title : host, tab.url, '收藏');
    }
  }

  private showEditor(site: Site | null, initName: string, initUrl: string, titleText: string): void {
    this.editorCtrl = new CustomDialogController({
      builder: SiteEditorDialog({
        titleText: titleText,
        initName: initName,
        initUrl: initUrl,
        submit: (name: string, url: string): void => this.saveSite(site, name, url)
      }),
      autoCancel: true
    });
    this.editorCtrl.open();
  }

  private saveSite(original: Site | null, name: string, url: string): void {
    // 规则全在 domain BookmarkService（与主页「添加/编辑」共用同一实现）
    const result = AppGraph.bookmarks().save(original, name, url);
    if (result.outcome === SaveOutcome.EMPTY_URL) {
      this.toast('地址不能为空');
      return;
    }
    const base = result.outcome === SaveOutcome.SAVED ? '已收藏' : '已保存';
    this.toast(result.outsideWhitelist ? `${base}（该域名不在白名单，访问会被拦截）` : base);
    this.updateStar();
    this.homeTick = this.homeTick + 1;
  }

  // ---------- 回调 ----------

  private onTabTitle(id: number, title: string): void {
    this.tabList.rename(id, title);
    this.metaVersion = this.metaVersion + 1;
  }

  private onTabPageEnd(id: number, url: string): void {
    if (url === '' || url === 'about:blank') {
      return; // 空标签页不写入 tab.url：概览层与地址栏保持占位文案
    }
    // 真的有一页加载成功 → 之前那张拦截卡片与该标签的拦截记忆都该消失
    this.blockedByTab.delete(id);
    if (id === this.tabList.currentId()) {
      this.blockedUrl = '';
    }
    this.tabList.update(id, url);
    // 导航完成才是"这个标签现在是什么地址"的真相：不在这里写盘，
    // 恢复时会拿到创建时的旧 URL（新标签甚至是空串）。
    this.persistTabsThrottled();
    // 只有当前标签的导航才写 lastUrl / 刷地址栏——后台标签不得抢焦点（Android onCurrentTabUiChanged 语义）
    if (id === this.tabList.currentId()) {
      AppGraph.settings().setLastUrl(url);
      this.syncAddress();
    }
    this.metaVersion = this.metaVersion + 1;
  }

  /**
   * 主框架被白名单拦下、文档已卸载成空白页。
   * 不能像以前那样把 URL 清掉：页面已经没了，地址栏也没了，用户连「被拦的是什么地址」
   * 都拿不到，更别说复制。现在把 URL 留在标签上（地址栏可见、可选中复制），
   * 同时弹一张拦截卡片，提供「复制链接」。
   */
  private onTabBlocked(id: number, blockedUrl: string, unloaded: boolean): void {
    this.blockedByTab.set(id, blockedUrl);
    if (unloaded) {
      // 文档已被卸成 about:blank：地址栏显示这条失败地址（等同浏览器的错误页），
      // 既不会和页面内容打架，也顺手成了第二个可复制的入口。
      this.tabList.update(id, blockedUrl);
    }
    // unloaded=false：页面还停在原处，地址栏必须保持原样，只在卡片里给出被拦地址。
    // 但无论哪条路径，这个标签的标题/进度都属于"上一页"，不清掉就会在标签概览里
    // 出现「旧标题 + 被拦 URL」这种自相矛盾的条目。
    this.tabList.rename(id, '');
    this.tabList.setProgress(id, 0);
    this.persistTabs(); // 立即落盘（被拦标签会被写成空串），别等节流窗口
    if (id === this.tabList.currentId()) {
      this.progress = 0;
      this.blockedUrl = blockedUrl;
      this.syncAddress();
    }
    this.metaVersion = this.metaVersion + 1;
  }

  private onTabProgress(id: number, progress: number): void {
    // 每个标签各自记录进度：切回仍在加载的标签要能恢复进度条（Android attachTab 同语义）
    this.tabList.setProgress(id, progress);
    if (id === this.tabList.currentId()) {
      this.progress = progress;
    }
  }

  private toast(message: string): void {
    this.notifier?.show(message);
  }

  // ---------- 渲染辅助 ----------

  /** 白名单拦截提示卡：URL 可选中复制 + 一键复制，避免「拦了又抄不出来」的死局。 */
  @Builder
  private blockedLayer() {
    Column() {
      Column() {
        Text('访问被拦截')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F1F1F')
        Text('该域名不在白名单，页面没有加载。地址如下，可复制后到别处使用：')
          .fontSize(13)
          .fontColor('#6B7280')
          .lineHeight(19)
          .margin({ top: 6 })
        // 用可滚动容器装完整 URL：maxLines + Ellipsis 会把长地址截断，
        // 用户手选复制时看到的和实际复制的不是一回事。
        Scroll() {
          Text(this.blockedUrl)
            .fontSize(13)
            .fontColor('#1F1F1F')
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding(10)
        }
        .constraintSize({ maxHeight: 132 })
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .backgroundColor('#F2F3F5')
        .borderRadius(9)
        .margin({ top: 10 })
        Row({ space: 10 }) {
          Button('复制链接')
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#1F1F1F')
            .onClick(() => {
              const ok = AppGraph.copyText(this.blockedUrl);
              this.toast(ok ? '已复制链接' : '复制失败');
            })
          Button('知道了')
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor('#1F1F1F')
            .backgroundColor('#F2F3F5')
            .onClick(() => {
              this.blockedUrl = '';
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('88%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(14)
      .shadow({ radius: 20, color: '#24000000', offsetY: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#33000000')
  }

  /** 标签创建时的初始地址：空标签用 about:blank。后台标签也带着真实 URL，
   *  但由 BrowserWeb 在"变成可见"时自己加载（见 active 属性），父层不隔空点隐藏控制器。 */
  private initialUrlOf(id: number): string {
    const tab = this.tabList.find(id);
    if (tab === null || tab.url === '') {
      return 'about:blank';
    }
    return tab.url;
  }

  /** 概览层快照：读 metaVersion 建立 @State 依赖，保证标题变化后能刷新。 */
  private tabsSnapshot(): TabMeta[] {
    // 显式读 metaVersion：在 build 期间建立 @State 依赖，标题/URL 变化后概览层才刷新
    if (this.metaVersion < 0) {
      return [];
    }
    return this.tabList.all();
  }

  onBackPress(): boolean {
    // 返回次序与 Android 一致：退出全屏 → 关标签概览 → 关主页覆盖层 → 网页后退 → 回主页
    if (this.fullscreen) {
      this.fullscreen = false;
      return true;
    }
    if (this.blockedUrl !== '') {
      this.blockedUrl = '';
      return true;
    }
    if (this.switcherVisible) {
      this.switcherVisible = false;
      return true;
    }
    if (this.showHome) {
      if (this.homeOverlay) {
        this.closeHomeOverlay();
        return true;
      }
      return false; // 独立主页：交给系统退出
    }
    // 浏览中：先网页后退，退无可退回主页覆盖层；再按一次则退出应用（与 Android 同终点）
    if (this.currentId < 0) {
      this.showHomeLayer();
      return true;
    }
    try {
      const ctrl = this.controllerOf(this.currentId);
      if (ctrl.accessBackward()) {
        ctrl.backward();
        this.backHomeOnce = false;
        return true;
      }
    } catch (e) {
      // controller 未 attach
    }
    if (this.backHomeOnce) {
      // 已经回过一次主页覆盖层、用户又从覆盖层回到浏览态且仍无后退历史 → 交给系统退出。
      // 少了这一句就是一个死循环：回主页 → 关覆盖层 → 又回主页，永远退不出应用。
      return false;
    }
    this.backHomeOnce = true;
    this.showHomeLayer();
    return true;
  }

  build() {
    Stack() {
      // ---------- 浏览层 ----------
      Column() {
        // 顶部操作栏：全屏时整条隐藏（对应 Android ImmersiveController 的 bars）
        if (!this.fullscreen) {
          Row() {
            Image($r('app.media.ic_home'))
              .width(32)
              .height(32)
              .padding(7)
              .onClick(() => this.showHomeLayer())
            TextInput({ text: this.address, placeholder: '输入网址' })
              .layoutWeight(1)
              .height(34)
              .fontSize(14)
              .fontColor('#1F1F1F')
              .placeholderColor('#9AA0A6')
              .backgroundColor('#F2F3F5')
              .borderRadius(9)
              .padding({ left: 10, right: 10 })
              .onEditChange((isEditing: boolean) => {
                this.addressEditing = isEditing;
              })
              .onChange((v: string) => {
                this.address = v;
              })
              .onSubmit(() => {
                this.addressEditing = false;
                this.openUrl(this.address, true);
              })
            Image($r('app.media.ic_refresh'))
              .width(32)
              .height(32)
              .padding(7)
              .onClick(() => {
                try {
                  this.controllerOf(this.currentId).refresh();
                } catch (e) {
                  // Web 尚未创建
                }
              })
            Image(this.starred ? $r('app.media.ic_star_on') : $r('app.media.ic_star'))
              .width(32)
              .height(32)
              .padding(7)
              .onClick(() => this.bookmarkCurrent())
            Stack({ alignContent: Alignment.TopEnd }) {
              Image($r('app.media.ic_tabs'))
                .width(32)
                .height(32)
                .padding(7)
              Text(`${this.tabIds.length}`)
                .fontSize(9)
                .fontColor(Color.White)
                .backgroundColor('#1F1F1F')
                .borderRadius(7)
                .width(14)
                .height(14)
                .textAlign(TextAlign.Center)
            }
            .width(34)
            .height(34)
            .onClick(() => {
              this.switcherVisible = !this.switcherVisible;
            })
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .backgroundColor(Color.White)
          .alignItems(VerticalAlign.Center)

          Divider()
            .color('#EDEDED')
            .strokeWidth(0.5)
        }

        if (this.progress > 0 && this.progress < 100) {
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color('#1F1F1F')
        }

        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.tabIds, (id: number) => {
            BrowserWeb({
              tabId: id,
              controller: this.controllerOf(id),
              initialUrl: this.initialUrlOf(id),
              active: id === this.currentId,
              onProgress: (tabId: number, p: number): void => this.onTabProgress(tabId, p),
              onTitle: (tabId: number, t: string): void => this.onTabTitle(tabId, t),
              onPageEnd: (tabId: number, u: string): void => this.onTabPageEnd(tabId, u),
              onBlocked: (tabId: number, blockedUrl: string, unloaded: boolean): void =>
                this.onTabBlocked(tabId, blockedUrl, unloaded),
              // 点链接另开标签：复用已有的 openUrl(reuseCurrent=false) —— 建标签、切过去、
              // 由新 BrowserWeb 的 initialUrl 首次导航，走的是已经验证过的同一条路径。
              onOpenInNewTab: (url: string): void => this.openUrl(url, false)
            })
              .visibility(id === this.currentId ? Visibility.Visible : Visibility.None)
          }, (id: number): string => id.toString())

          // 悬浮全屏按钮：可拖动、位置记忆、边界钳制（几何规则在 domain/FabGeometry）
          FullscreenFab({
            fullscreen: this.fullscreen,
            containerW: this.webW,
            containerH: this.webH,
            onToggle: (): void => {
              this.fullscreen = !this.fullscreen;
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.webW = parseFloat(String(newValue.width));
          this.webH = parseFloat(String(newValue.height));
        })
      }
      .width('100%')
      .height('100%')
      .visibility(this.showHome ? Visibility.None : Visibility.Visible)

      // ---------- 主页层（独立或覆盖） ----------
      if (this.showHome) {
        HomeView({
          tick: this.homeTick,
          overlayMode: this.homeOverlay,
          onClose: (): void => this.closeHomeOverlay(),
          openSite: (url: string): void => this.openUrl(url, true),
          removeSite: (site: Site): void => this.removeSite(site)
        })
      }

      // ---------- 标签概览 ----------
      if (this.switcherVisible) {
        TabSwitcher({
          tabs: this.tabsSnapshot(),
          currentId: this.currentId,
          onSelect: (id: number): void => this.selectTab(id),
          onClose: (id: number): void => this.closeTab(id),
          onCloseOthers: (id: number): void => this.closeOthers(id),
          onNew: (): void => this.newTab(),
          onDismiss: (): void => {
            this.switcherVisible = false;
          }
        })
      }

      // ---------- 白名单拦截提示（URL 可复制，避免「拦了又抄不出来」） ----------
      if (this.blockedUrl !== '') {
        this.blockedLayer()
      }
    }
    .width('100%')
    .height('100%')
  }
}