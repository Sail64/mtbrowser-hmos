import { CertInfo, CertKind, CertVerdict } from './model/CertModels';
import type { CertificateAdvisor } from './CertificateAdvisor';
import type { CertReminderScheduler } from './CertReminderScheduler';
import type { ProbeThrottle } from './ProbeThrottle';
import { UrlLite } from './UrlLite';

/** 当前页面服务端证书来源（平台无关端口；ArkWeb 实现见 platform/ArkWebCertificateSource）。 */
export interface CertificateSource {
  /** 取当前站点服务器证书叶子；失败/无证书返回 null（静默，与 Android prober 语义一致）。 */
  currentServerCert(): Promise<CertInfo | null>;
}

/** 提醒展示出口（UI 适配）。 */
export interface CertReminderNotifier {
  show(message: string): void;
}

/**
 * 服务端证书到期提醒编排（对应 Android ServerCertCheckEnhancer）。
 * 规则全部委托端口：限频 ProbeThrottle、去重 CertReminderScheduler、
 * 评估/文案 CertificateAdvisor；本类只做编排，无平台依赖。
 */
export class ServerCertReminderService {
  private source: CertificateSource;
  private advisor: CertificateAdvisor;
  private throttle: ProbeThrottle;
  private reminders: CertReminderScheduler;
  private notifier: CertReminderNotifier;
  /** 正在探测中的 host：防止同一 host 并发重复取证书 */
  private inFlight: Set<string> = new Set();

  constructor(source: CertificateSource, advisor: CertificateAdvisor, throttle: ProbeThrottle,
    reminders: CertReminderScheduler, notifier: CertReminderNotifier) {
    this.source = source;
    this.advisor = advisor;
    this.throttle = throttle;
    this.reminders = reminders;
    this.notifier = notifier;
  }

  /** 页面加载完成时调用（每 host 最多 24h 一次真实取证书）。 */
  onPageEnd(url: string): void {
    const host = UrlLite.hostOf(url);
    if (host === null) {
      return;
    }
    if (!this.throttle.shouldRun(host)) {
      return;
    }
    // 同一 host 的探测去重：shouldRun 与 markRun 之间隔着一次异步取证书，
    // 重定向/多标签会在记账前重复发起同一 host 的探测。
    if (this.inFlight.has(host)) {
      return;
    }
    this.inFlight.add(host);
    this.source.currentServerCert()
      .then((cert: CertInfo | null) => {
        this.inFlight.delete(host);
        if (cert === null) {
          // 取不到证书 ≠ 证书正常：不记账，下次页面加载再试。
          // （getCertificate 是本地调用，重试成本低；记账会把 24h 窗口白白烧掉）
          return;
        }
        this.throttle.markRun(host);
        const verdict = this.advisor.evaluate(cert, CertKind.SERVER);
        if (verdict === CertVerdict.VALID) {
          return;
        }
        if (this.reminders.shouldRemind(host, CertKind.SERVER)) {
          this.reminders.markReminded(host, CertKind.SERVER);
          this.notifier.show(this.advisor.message(verdict, CertKind.SERVER, this.advisor.daysLeft(cert)));
        }
      })
      .catch((): void => {
        this.inFlight.delete(host);
        // 取证书失败静默（页面本身可能压根没走到 TLS 完成）
      });
  }
}
