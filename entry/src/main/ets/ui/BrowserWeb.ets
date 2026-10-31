import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppGraph } from '../app/AppGraph';
import { UrlLite } from '../domain/UrlLite';
import { NavigationDecision } from '../domain/model/CertModels';
import { SslDecisionKind } from '../domain/SslTrustPolicy';
import { sslErrorLabel } from '../domain/SslErrorLabels';
import { ServerCertReminderService, CertReminderNotifier } from '../domain/ServerCertReminderService';
import { ToastNotifier } from './ToastNotifier';

/**
 * 同一时刻每个 host 只允许一个 SSL 告警对话框（Android showingSslDialogs 的等价物）。
 * 放在模块作用域：多标签共享，避免同一站点在两个标签里同时弹框。
 */
const showingSslHosts: Set<string> = new Set();

/** 400 证书清理冷却（Android CERT_CLEAR_COOLDOWN_MS）：防错误风暴下反复清缓存+刷新。 */
const CERT_CLEAR_COOLDOWN_MS: number = 5000;

const DOMAIN = 0x0001;
const TAG = 'BrowserWeb';

/**
 * 单个标签的 Web 视图（对应 Android web/BrowserWebViewClient + WebViewConfigurator 的合并形态）。
 *
 * 铁律：
 * 1. 每个实例 = 一个标签 = 一个 WebviewController，由 Index 持有并传入；
 * 2. 全项目只有这里接 ArkWeb 事件，每个回调只做三步：提取参数 → 问 domain → 执行；
 * 3. 所有 Web 属性集中在此，多标签下不会四处漂移。
 */
@Component
export struct BrowserWeb {
  /** 所属标签 id（回调时回传给上层定位标签） */
  tabId: number = -1;
  /** 该标签专属控制器（Index 的 Map 持有，生命周期长于本组件） */
  controller: webview.WebviewController = new webview.WebviewController();
  /** 该标签的初始地址：仅首次挂载时消费一次，之后导航一律走 controller.loadUrl() */
  initialUrl: string = 'about:blank';
  /**
   * 是否为当前可见标签。后台标签不发起导航（避免冷启动时 N 个 mTLS 标签同时弹证书框），
   * 变成可见时由本组件自己补上首次导航——不能让父层隔空点隐藏的控制器，
   * 那样会打到一个还没 attach 的 controller 上，表现为"地址栏有 URL、页面永远空白"。
   */
  @Prop @Watch('onActiveChanged') active: boolean = false;

  onProgress: (tabId: number, progress: number) => void = (): void => {};
  onTitle: (tabId: number, title: string) => void = (): void => {};
  onPageEnd: (tabId: number, url: string) => void = (): void => {};
  /** 主框架被白名单拦下且文档已被卸载：上层需要清掉该标签记录里的旧 URL */
  onBlocked: (tabId: number, blockedUrl: string) => void = (): void => {};

  private reminderService: ServerCertReminderService | null = null;
  private notifier: CertReminderNotifier | null = null;
  /**
   * 首次导航目标。Web 的 src 恒为 about:blank：src 是普通参数，若跟着标签 URL 走，
   * 父组件任何一次重建都可能把它变成"意外重载"。首次加载只在这里发生一次。
   */
  private pendingUrl: string = '';
  private initialLoadStarted: boolean = false;
  /** per-host 的上次证书清理时间（冷却用） */
  private certClearAt: Map<string, number> = new Map();
  /** 主文档是否已提交：仅用于 onPageEnd 语义，不再参与 SSL 归因（见 handleSslError） */
  private mainFrameCommitted: boolean = false;
  /** 当前页已提示过「子资源被拦」，避免刷屏 */
  private subresourceWarned: boolean = false;
  /** 被白名单拦下的 URL：其 onPageEnd 不得写回 tab.url / lastUrl */
  private blockedUrl: string = '';
  /** 本标签实际发生过客户端证书握手的 host（400 清理只对这些 host 生效） */
  private mtlsHosts: Set<string> = new Set();
  /** clearClientAuthenticationCache 在本机型是否可用（不可用就别说"已修复"） */
  private certCacheClearOk: boolean = true;
  /** 本实例登记进 showingSslHosts 的 host（销毁时负责撤销） */
  private sslHostsShown: Set<string> = new Set();
  /** 本轮导航是否已提示过加载失败（避免错误风暴刷屏） */
  private loadErrorNotified: boolean = false;
  /** 文件选择器是否已拉起（重入闸：picker 打开期间不允许再起一个） */
  private filePicking: boolean = false;

  aboutToAppear(): void {
    this.notifier = new ToastNotifier(this.getUIContext().getPromptAction());
    this.reminderService = AppGraph.makeCertReminder(this.controller, this.notifier);
    this.pendingUrl = this.initialUrl;
  }

  aboutToDisappear(): void {
    // 标签关闭时若有未决的 SSL 弹框，promise 不会再回调：把本实例登记过的 host 清掉，
    // 否则该 host 在本进程内会被 showSslHosts 永久挡住，之后所有 SSL 错误都被静默取消。
    for (const h of this.sslHostsShown) {
      showingSslHosts.delete(h);
    }
    this.sslHostsShown.clear();
    AppGraph.persistCookies(true);
  }

  /**
   * 补上首次导航。只在"可见"时做：隐藏状态的 Web 控制器不一定就绪，
   * 盲调 loadUrl 会静默失败（表现为地址栏有 URL、页面永远白）。
   */
  private tryLoadPending(attempt: number): void {
    if (this.initialLoadStarted || !this.active) {
      return;
    }
    if (this.pendingUrl === '' || this.pendingUrl === 'about:blank') {
      return;
    }
    try {
      this.controller.loadUrl(this.pendingUrl);
      this.initialLoadStarted = true;
    } catch (e) {
      // 引擎还没 attach：短延迟再试，有界（6 次 × 120ms）
      if (attempt >= 6) {
        hilog.error(DOMAIN, TAG, 'initial loadUrl gave up: %{public}s', JSON.stringify(e));
        this.toast('页面加载失败，可点 ↻ 重试');
        return;
      }
      setTimeout(() => {
        this.tryLoadPending(attempt + 1);
      }, 120);
    }
  }

  /** 从后台切到前台：把一直挂着的首次导航补上。
   *  必须等一帧再发：切标签的同一帧里组件刚从 Visibility.None 变可见，
   *  此时 loadUrl 会被内核立刻 ERR_ABORTED(-3) 掐掉（实测日志），页面永远停在 about:blank。 */
  private onActiveChanged(): void {
    if (!this.active) {
      return;
    }
    setTimeout(() => {
      this.tryLoadPending(0);
    }, 250);
  }

  private toast(message: string): void {
    this.notifier?.show(message);
  }

  /**
   * 回传文件选择结果给内核。
   * 必须每次都回（取消回空数组），否则该 file input 会永久挂起、再点没反应；
   * 标签已被关掉时 handler 可能已失效，所以两层都包 try。
   */
  private deliverFiles(result: FileSelectorResult, uris: string[]): void {
    try {
      result.handleFileList(uris);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'handleFileList failed (page gone?): %{public}s', JSON.stringify(e));
    }
  }

  private openExternal(url: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
      entities: ['entity.system.browsable']
    };
    ctx.startAbility(want).catch((e: Error) => {
      // 引擎的英文异常（常带 16000001 之类数字码）只进日志，界面给固定中文
      hilog.error(DOMAIN, TAG, 'startAbility failed for external url: %{public}s', JSON.stringify(e));
      this.toast(UrlLite.schemeOf(url) === 'tel' || UrlLite.schemeOf(url) === 'sms'
        ? '无法打开拨号/短信应用' : '无法用其他应用打开该链接');
    });
  }

  private handleSslError(event: SslErrorEvent): void {
    // onSslErrorEvent 自带 url + isMainFrame：不再用「主文档是否已提交」猜归因，
    // 也不再用 controller.getUrl()（那是上一个已提交文档的地址，跨站跳转时会张冠李戴，
    // 导致「弹框写 A 站、实际放行 B 站」）。
    if (!event.isMainFrame) {
      // 子资源/iframe 的证书错误：直接取消，不弹框、不授会话豁免。
      // 否则一个第三方端点的坏证书就能给整站换来「本会话免检」。
      try {
        event.handler.handleCancel();
      } catch (e) {
        // handler 已失效
      }
      if (!this.subresourceWarned) {
        this.subresourceWarned = true;
        this.toast('已阻止证书校验失败的子资源');
      }
      hilog.warn(DOMAIN, TAG, 'ssl error on subresource cancelled, code=%{public}d', event.error);
      return;
    }
    // 主框架：host 取自本次出错请求的 URL；取不到可靠 host 时一律拒绝（fail-closed）
    const hostOrNull: string | null = UrlLite.hostOf(event.url !== '' ? event.url : event.originalUrl);
    if (hostOrNull === null || hostOrNull === '') {
      try {
        event.handler.handleCancel();
      } catch (e) {
        // handler 已失效
      }
      return;
    }
    // 显式收敛成非空 string：ArkTS 不会把窄化结果带进闭包
    const host: string = hostOrNull;
    const policy = AppGraph.sslTrustPolicy();
    // error 是 SDK 的 SslError 数字码，必须经 domain 映射成中文（安卓侧同样做映射）
    const decision = policy.onError(host, sslErrorLabel(event.error));
    if (decision.kind === SslDecisionKind.PROCEED) {
      event.handler.handleConfirm();
      return;
    }
    if (decision.kind === SslDecisionKind.DENY) {
      // 策略层否决权不得被 UI 的"仍要继续"抹掉
      event.handler.handleCancel();
      return;
    }
    // ASK_USER：同一 host 同时只弹一个框，其余直接取消
    if (showingSslHosts.has(host)) {
      event.handler.handleCancel();
      return;
    }
    showingSslHosts.add(host);
    this.sslHostsShown.add(host);
    this.getUIContext().getPromptAction().showDialog({
      title: 'SSL 证书警告',
      message: `${decision.reason}\n\n是否仍要继续访问 ${host}？\n（本次运行内不再询问该站点）`,
      buttons: [
        { text: '取消', color: '#333333' },
        { text: '仍要继续', color: '#D9534F' }
      ]
    }).then((res) => {
      showingSslHosts.delete(host);
      if (res.index === 1) {
        policy.grantSessionExemption(host);
        try {
          event.handler.handleConfirm();
        } catch (e) {
          // handler 已失效（页面已关闭）
        }
      } else {
        try {
          event.handler.handleCancel();
        } catch (e) {
          // handler 已失效
        }
      }
    }).catch(() => {
      showingSslHosts.delete(host);
      try {
        event.handler.handleCancel();
      } catch (e) {
        // handler 已失效
      }
    });
  }

  private handleClientAuth(event: OnClientAuthenticationEvent): void {
    const host = event.host;
    // 白名单闸门必须排在缓存之前：缓存命中的路径一旦先行 confirm，
    // 「只给白名单站点发证书」的约束就被绕过了（站点被移出名单后其 iframe 仍可复用授权）。
    if (!AppGraph.domainWhitelist().allows(`https://${host}:${event.port}/`)) {
      hilog.warn(DOMAIN, TAG, 'client cert request from non-whitelisted host ignored: %{public}s', host);
      this.toast('非白名单站点请求客户端证书，已忽略');
      event.handler.ignore();
      return;
    }
    const selector = AppGraph.clientCertSelector();
    const cached = selector.cachedIdentity(host);
    if (cached !== null) {
      try {
        event.handler.confirm(cached);
        this.mtlsHosts.add(host);
        return;
      } catch (e) {
        // 缓存的凭据已失效（被卸载等）：清缓存重选
        selector.clearIdentity(host);
      }
    }
    selector.chooseIdentity(host, event.port, (identity: string | null): void => {
      if (identity !== null) {
        try {
          event.handler.confirm(identity);
          this.mtlsHosts.add(host);
          return;
        } catch (e) {
          selector.clearIdentity(host);
          // 用户明明选了证书却没送出去：必须说清楚，不能静默降级为"无证书继续"
          this.toast('证书未能用于本次连接');
          hilog.error(DOMAIN, TAG, 'confirm(identity) failed: %{public}s', JSON.stringify(e));
        }
      }
      // ignore() 而非 cancel()：等价 Android request.ignore()——本次不带证书继续，
      // 后续导航可再次发起证书请求；cancel() 会终止该次请求
      event.handler.ignore();
    });
  }

  private handleHttpError(event: OnHttpErrorReceiveEvent): void {
    // 主框架 400 + 该 host 存过证书 = 服务端拒绝客户端证书，清缓存让下次重新选
    const isMainFrame = event.request.isMainFrame();
    if (!isMainFrame || event.response.getResponseCode() !== 400) {
      return;
    }
    let host: string | null = null;
    try {
      host = UrlLite.hostOf(event.request.getRequestUrl());
    } catch (e) {
      host = null;
    }
    if (host === null) {
      return;
    }
    const selector = AppGraph.clientCertSelector();
    if (selector.cachedIdentity(host) === null) {
      return;
    }
    // 400 也可能来自错误路径/反向代理/请求头过大，不一定是"服务端拒绝客户端证书"。
    // 只有本标签确实在这个 host 上完成过 mTLS 握手，才允许销毁用户的证书绑定。
    if (!this.mtlsHosts.has(host)) {
      hilog.warn(DOMAIN, TAG, 'main-frame 400 on %{public}s without prior mTLS handshake; keep binding', host);
      return;
    }
    const now = Date.now();
    const last = this.certClearAt.get(host);
    if (last !== undefined && now - last < CERT_CLEAR_COOLDOWN_MS) {
      return; // 冷却期内不再清+刷新，避免错误风暴
    }
    this.certClearAt.set(host, now);
    selector.clearIdentity(host);
    // 同时清内核侧客户端证书缓存，否则 refresh 可能仍复用旧证书 → 400 循环
    if (this.certCacheClearOk) {
      try {
        this.controller.clearClientAuthenticationCache();
      } catch (e) {
        this.certCacheClearOk = false;
        hilog.warn(DOMAIN, TAG, 'clearClientAuthenticationCache unsupported: %{public}s', JSON.stringify(e));
      }
    }
    // 提示必须与实际做到的事一致：内核缓存没清掉就别宣称"已修复"
    this.toast(this.certCacheClearOk
      ? '客户端证书已失效，请重新选择'
      : '已重置证书选择；内核缓存未能清除，可能需重启应用');
    try {
      this.controller.refresh();
    } catch (e) {
      // 页面已不可用，忽略
    }
  }

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width('100%')
      .height('100%')
      // 首次导航在 onPageEnd(about:blank) 里发起：这里不能抢跑。
      // （实测在 onControllerAttached 里 loadUrl，会被组件自身 about:blank 的
      //   首帧导航顶掉，表现为冷启动白屏 + ERR_ABORTED）
      // 安全基线：禁混合内容、禁本地文件访问
      .mixedMode(MixedMode.None)
      .fileAccess(false)
      // ArkWeb 默认 false。SPA（Hermes WebUI）此时 localStorage === null，
      // 首屏后的 JS 直接抛 TypeError，页面渲染正常但全部交互失效。
      .domStorageAccess(true)
      .databaseAccess(true)
      .javaScriptAccess(true)
      // 深色模式：跟随系统，但**不强制**给网页反色。
      // 实测 forceDarkAccess(true) 会把 LibreChat 整页打成白屏（HTTP 200、无 JS 报错），
      // 与 Android 的 FORCE_DARK_AUTO 同名不同命，宁可少一个效果也不能白屏。
      .darkMode(WebDarkMode.Auto)
      .forceDarkAccess(false)
      // JS 报错必须落地，否则 ArkWeb 只把 console 丢进 hilog 洪水里
      .onConsole((event?: OnConsoleEvent): boolean => {
        const msg = event?.message;
        if (msg !== undefined) {
          const level = msg.getMessageLevel();
          if (level === MessageLevel.Error || level === MessageLevel.Warn) {
            hilog.error(0x0001, 'ArkConsole',
              `${msg.getSourceId()}:${msg.getLineNumber()} ${msg.getMessage()}`);
          }
        }
        return false;
      })
      .onControllerAttached(() => {
        // 引擎到这里才算真正初始化完成：内核下载委托只能在此时注册
        // （提前注册会让 ArkWeb 原生层直接崩溃）。
        AppGraph.configureDownloader();
      })
      .onProgressChange((event: OnProgressChangeEvent): void => {
        this.onProgress(this.tabId, event.newProgress);
      })
      .onTitleReceive((event: OnTitleReceiveEvent): void => {
        // about:blank 也会报标题（内容就是 "about:blank"）：它不是页面标题，
        // 写进去会让概览层显示成 about:blank。
        const t = event.title;
        if (t === undefined || t === '' || t === 'about:blank') {
          return;
        }
        this.onTitle(this.tabId, t);
      })
      .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
        const data = event?.data;
        if (data === undefined) {
          return false;
        }
        const url = data.getRequestUrl();
        let current = '';
        try {
          current = this.controller.getUrl();
        } catch (e) {
          current = '';
        }
        const decision = AppGraph.navigationPolicy().decide(url, current);
        if (decision === NavigationDecision.OPEN_EXTERNAL) {
          this.openExternal(url);
          return true;
        }
        if (decision === NavigationDecision.BLOCK) {
          // file:/javascript:/data:/blob: 等危险 scheme：不外抛也不加载
          this.toast('已拦截不安全的跳转');
          return true;
        }
        if (data.isMainFrame() && !AppGraph.domainWhitelist().allows(url)) {
          // 同一个拦截归宿：URL 要留在界面里（卡片 + 地址栏），不能只 toast 一句
          this.onBlocked(this.tabId, url);
          this.toast('域名不在白名单，已拦截');
          return true;
        }
        return false;
      })
      // 白名单兜底：302 重定向 / 脚本跳转不经过 onLoadIntercept
      // （Android 用 doUpdateVisitedHistory 在同一位置补位）
      .onNavigationEntryCommitted((details: LoadCommittedDetails): void => {
        if (!details.isMainFrame || details.isSameDocument) {
          return;
        }
        // 主文档已提交：此后到达的 SSL 错误必然是子资源的
        this.mainFrameCommitted = true;
        if (AppGraph.domainWhitelist().allows(details.url)) {
          this.blockedUrl = '';
          return;
        }
        // onNavigationEntryCommitted 在文档已提交后才触发：stop() 只停剩余子资源，
        // 页面脚本可能已经执行过。所以必须把文档卸载掉（退回空白页），
        // 不能把它留在屏幕上还跟用户说「已拦截」。
        this.blockedUrl = details.url;
        hilog.warn(DOMAIN, TAG, 'blocked committed navigation: %{public}s', details.url);
        try {
          this.controller.stop();
        } catch (e) {
          // 页面已结束
        }
        try {
          this.controller.loadUrl('about:blank');
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'failed to unload blocked page: %{public}s', JSON.stringify(e));
        }
        const blockedHost: string = UrlLite.hostOf(details.url) ?? details.url;
        // 把被拦的完整 URL 交回上层：页面已卸成空白页，用户唯一还能拿到这条地址的地方
        // 就是应用自己（地址栏 + 拦截提示卡）。只 toast 一句「已拦截」等于把 URL 吞了，
        // 用户既看不到也复制不出来——那才是死局。
        this.onBlocked(this.tabId, details.url);
        this.toast(`已阻止加载：${blockedHost}（不在白名单）`);
      })
      .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
        // 网页里的 <input type="file">（LibreChat 附件、Hermes 上传都走这里）
        if (this.filePicking) {
          // picker 已经开着：再点一次 input 不再拉起第二个，但也不能把内核晾着
          this.deliverFiles(event.result, []);
          return true;
        }
        this.filePicking = true;
        const multiple = event.fileSelector.getMode() === FileSelectorMode.FileOpenMultipleMode;
        AppGraph.pickFiles(event.fileSelector.getAcceptType(), multiple)
          .then((uris: string[]) => {
            this.filePicking = false;
            this.deliverFiles(event.result, uris);
          })
          .catch((e: Error) => {
            this.filePicking = false;
            hilog.error(DOMAIN, TAG, 'file selector failed: %{public}s', JSON.stringify(e));
            this.deliverFiles(event.result, []);
          });
        return true; // 已接管
      })
      .onErrorReceive((event?: OnErrorReceiveEvent): void => {
        if (event === undefined) {
          return;
        }
        const info = event.error;
        const req = event.request;
        const code = info.getErrorCode();
        // -3 ERR_ABORTED：我们自己 stop()/loadUrl('about:blank') 拦截页面、切标签、
        //   首帧 about:blank 被新导航顶掉，都会产生它；这不是"加载失败"，不能弹提示。
        // -20 ERR_BLOCKED_BY_CLIENT：onLoadIntercept 拦下的导航。
        if (code === -3 || code === -20) {
          return;
        }
        // 只对主框架提示：子资源失败（图片/埋点）不该打断用户
        if (req === undefined || !req.isMainFrame()) {
          hilog.warn(DOMAIN, TAG, 'subresource load error: %{public}s (code=%{public}d)', info.getErrorInfo(), code);
          return;
        }
        hilog.error(DOMAIN, TAG, 'main frame load error: %{public}s (code=%{public}d)', info.getErrorInfo(), code);
        if (!this.loadErrorNotified) {
          this.loadErrorNotified = true;
          this.toast('页面加载失败，可点 ↻ 重试');
        }
      })
      .onSslErrorEvent((event: SslErrorEvent): void => {
        this.handleSslError(event);
      })
      .onClientAuthenticationRequest((event: OnClientAuthenticationEvent): void => {
        this.handleClientAuth(event);
      })
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
        this.handleHttpError(event);
      })
      .onPageEnd((event?: OnPageEndEvent): void => {
        const url = event?.url ?? '';
        // 空白页加载结束：这才是发起首次导航的安全时机
        if (url === 'about:blank' || url === '') {
          this.tryLoadPending(0);
          return;
        }
        // 被白名单拦下的页面不得写回 tab.url / lastUrl
        if (url === this.blockedUrl) {
          return;
        }
        this.onPageEnd(this.tabId, url);
        this.reminderService?.onPageEnd(url);
        // 登录/会话 cookie 在这里写盘：SPA 登录后常有一次跳转或刷新，
        // 不落盘的话进程被杀就丢登录态。
        AppGraph.persistCookies(false);
        AppGraph.reportCookies(url, 'pageEnd');
      })
      .onPageBegin((event?: OnPageBeginEvent): void => {
        // 新一次主框架导航开始：提交前都不算 committed
        this.mainFrameCommitted = false;
        this.subresourceWarned = false;
        this.loadErrorNotified = false;
      })
      // SPA 的 pushState / hash 变化不触发 onPageEnd：地址栏与后台 URL 在这里同步
      // （等价 Android doUpdateVisitedHistory 的 URL 同步职责）
      .onRefreshAccessedHistory((event: OnRefreshAccessedHistoryEvent): void => {
        if (event.isMainFrame === false || event.url === '' || event.url === 'about:blank') {
          return;
        }
        this.onPageEnd(this.tabId, event.url);
      });
  }
}