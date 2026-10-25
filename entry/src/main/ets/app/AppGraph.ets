import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertificateAdvisor, DefaultCertificateAdvisor } from '../domain/CertificateAdvisor';
import { CertReminderScheduler } from '../domain/CertReminderScheduler';
import { ClientCertSelector } from '../domain/ClientCertSelector';
import { DomainWhitelist } from '../domain/DomainWhitelist';
import { webview } from '@kit.ArkWeb';
import { NavigationPolicy, DefaultNavigationPolicy } from '../domain/NavigationPolicy';
import { ProbeThrottle } from '../domain/ProbeThrottle';
import { ServerCertReminderService, CertReminderNotifier } from '../domain/ServerCertReminderService';
import { ArkWebCertificateSource } from '../platform/ArkWebCertificateSource';
import { SslTrustPolicy, DefaultSslTrustPolicy } from '../domain/SslTrustPolicy';
import { SiteRepository } from '../domain/SiteRepository';
import { PrefSiteRepository } from '../data/PrefSiteRepository';
import { PrefClientCertStore } from '../data/PrefClientCertStore';
import { PrefCertReminderStore } from '../data/PrefCertReminderStore';
import { PrefProbeThrottleStore } from '../data/PrefProbeThrottleStore';
import { SettingsStore } from '../data/SettingsStore';
import { CertManagerClientCertSelector } from '../platform/CertManagerClientCertSelector';
import { BookmarkService } from '../domain/BookmarkService';

const WHITELIST_FILE = 'domain_whitelist.txt';

/**
 * 轻量依赖容器：应用的组合根（对应 Android di/AppGraph.kt）。
 * 单 Ability 应用不值得引入 DI 框架；接口边界已在 domain 定义，
 * 将来替换实现只改这里。UI 只通过本类的访问器拿实现（check-arch R3）。
 */
export class AppGraph {
  private static _siteRepository: SiteRepository | undefined = undefined;
  private static _certAdvisor: CertificateAdvisor | undefined = undefined;
  private static _reminderScheduler: CertReminderScheduler | undefined = undefined;
  private static _clientCertSelector: ClientCertSelector | undefined = undefined;
  private static _sslTrustPolicy: SslTrustPolicy | undefined = undefined;
  private static _navigationPolicy: NavigationPolicy | undefined = undefined;
  private static _probeThrottle: ProbeThrottle | undefined = undefined;
  private static _domainWhitelist: DomainWhitelist | undefined = undefined;
  private static _settings: SettingsStore | undefined = undefined;
  private static _bookmarks: BookmarkService | undefined = undefined;

  /** EntryAbility.onCreate 调用。重复调用无副作用（幂等）。 */
  static init(context: common.UIAbilityContext): void {
    if (AppGraph._siteRepository !== undefined) {
      return;
    }
    const advisor = new DefaultCertificateAdvisor();
    AppGraph._certAdvisor = advisor;

    // 白名单必须先于 SSL 策略装配：策略要按白名单决定 DENY / ASK_USER
    const whitelist = new DomainWhitelist();
    whitelist.loadFrom(AppGraph.readWhitelist(context));
    AppGraph._domainWhitelist = whitelist;

    AppGraph._siteRepository = new PrefSiteRepository(context);
    AppGraph._clientCertSelector = new CertManagerClientCertSelector(context, new PrefClientCertStore(context));
    AppGraph._reminderScheduler = new PrefCertReminderStore(context);
    AppGraph._sslTrustPolicy = new DefaultSslTrustPolicy(whitelist);
    AppGraph._navigationPolicy = new DefaultNavigationPolicy();
    AppGraph._probeThrottle = new PrefProbeThrottleStore(context);
    AppGraph._settings = new SettingsStore(context);
    AppGraph._bookmarks = new BookmarkService(AppGraph._siteRepository, whitelist);
  }

  private static readWhitelist(context: common.UIAbilityContext): string | null {
    try {
      const bytes = context.resourceManager.getRawFileContentSync(WHITELIST_FILE);
      const decoder = util.TextDecoder.create('utf-8');
      const text = decoder.decodeToString(bytes);
      if (text.trim() === '') {
        // 文件存在但为空与"文件缺失"是两种不同的故障，日志必须能区分
        hilog.warn(0x0000, 'AppGraph', 'domain_whitelist.txt is empty; every site will be blocked');
      }
      return text;
    } catch (e) {
      // 文件缺失 = 空白名单 = 全拦（与 Android 版一致，故意保守），但必须留痕
      hilog.error(0x0000, 'AppGraph', 'failed to read %{public}s: %{public}s',
        WHITELIST_FILE, JSON.stringify(e));
      return null;
    }
  }

  private static ensure<T>(v: T | undefined, name: string): T {
    if (v === undefined) {
      throw new Error(`AppGraph not initialized when accessing ${name}`);
    }
    return v;
  }

  static siteRepository(): SiteRepository {
    return AppGraph.ensure(AppGraph._siteRepository, 'siteRepository');
  }

  static certAdvisor(): CertificateAdvisor {
    return AppGraph.ensure(AppGraph._certAdvisor, 'certAdvisor');
  }

  static reminderScheduler(): CertReminderScheduler {
    return AppGraph.ensure(AppGraph._reminderScheduler, 'reminderScheduler');
  }

  static clientCertSelector(): ClientCertSelector {
    return AppGraph.ensure(AppGraph._clientCertSelector, 'clientCertSelector');
  }

  static sslTrustPolicy(): SslTrustPolicy {
    return AppGraph.ensure(AppGraph._sslTrustPolicy, 'sslTrustPolicy');
  }

  static navigationPolicy(): NavigationPolicy {
    return AppGraph.ensure(AppGraph._navigationPolicy, 'navigationPolicy');
  }

  static probeThrottle(): ProbeThrottle {
    return AppGraph.ensure(AppGraph._probeThrottle, 'probeThrottle');
  }

  static domainWhitelist(): DomainWhitelist {
    return AppGraph.ensure(AppGraph._domainWhitelist, 'domainWhitelist');
  }

  /** 白名单是否为空（文件缺失或内容为空）：主页用它给出显式告警，而不是让用户撞「不在白名单」的墙。 */
  static whitelistIsEmpty(): boolean {
    return AppGraph.ensure(AppGraph._domainWhitelist, 'domainWhitelist').isEmpty();
  }

  static settings(): SettingsStore {
    return AppGraph.ensure(AppGraph._settings, 'settings');
  }

  /** 收藏保存的唯一入口（URL 规范化 / 去重 / 白名单提示都在它内部）。 */
  static bookmarks(): BookmarkService {
    return AppGraph.ensure(AppGraph._bookmarks, 'bookmarks');
  }

  /**
   * 证书提醒服务的装配工厂：编排端口全在 AppGraph（单例）；
   * CertificateSource 绑定每标签 WebviewController（UI 生命周期），由调用方传入 controller。
   * 多标签扩展时每个 tab 各调一次。
   */
  static makeCertReminder(controller: webview.WebviewController, notifier: CertReminderNotifier): ServerCertReminderService {
    return new ServerCertReminderService(
      new ArkWebCertificateSource(controller), AppGraph.certAdvisor(), AppGraph.probeThrottle(),
      AppGraph.reminderScheduler(), notifier);
  }
}
