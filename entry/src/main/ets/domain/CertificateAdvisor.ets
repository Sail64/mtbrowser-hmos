import { CertInfo, CertKind, CertVerdict } from './model/CertModels';

/**
 * 证书评估的唯一事实来源（SSOT）。
 * 所有需要判断证书健康度/组装文案的地方都必须问它，不允许各自计算天数。
 * （与 Android domain/CertificateAdvisor.kt 同源移植）
 */
export interface CertificateAdvisor {
  evaluate(cert: CertInfo, kind: CertKind): CertVerdict;
  daysLeft(cert: CertInfo): number;
  message(verdict: CertVerdict, kind: CertKind, daysLeft: number): string;
}

/** 一天毫秒数 */
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * 默认实现：客户端证书 30 天、服务端证书 14 天阈值（与 Android 版行为一致）。
 */
export class DefaultCertificateAdvisor implements CertificateAdvisor {
  private clientWarnDays: number;
  private serverWarnDays: number;

  constructor(clientWarnDays: number = 30, serverWarnDays: number = 14) {
    this.clientWarnDays = clientWarnDays;
    this.serverWarnDays = serverWarnDays;
  }

  daysLeft(cert: CertInfo): number {
    // 与 Java TimeUnit.MILLISECONDS.toDays 一致：向零截断
    return Math.trunc((cert.notAfterMs - Date.now()) / MS_PER_DAY);
  }

  evaluate(cert: CertInfo, kind: CertKind): CertVerdict {
    // 用时间戳判过期，而不是用 days：过期 2 小时时 daysLeft 会向零截断成 0，
    // 那样文案会变成「将在 0 天后过期」，把已过期的证书说成还有效。
    if (cert.notAfterMs < Date.now()) {
      return CertVerdict.EXPIRED;
    }
    const days = this.daysLeft(cert);
    const threshold = kind === CertKind.CLIENT ? this.clientWarnDays : this.serverWarnDays;
    if (days < threshold) {
      return CertVerdict.EXPIRING;
    }
    return CertVerdict.VALID;
  }

  message(verdict: CertVerdict, kind: CertKind, daysLeft: number): string {
    const label = kind === CertKind.CLIENT
      ? '客户端证书（注意：非服务端证书）'
      : '服务端证书（注意：非客户端证书）';
    if (verdict === CertVerdict.EXPIRED) {
      return `${label}已过期，请立即更新。`;
    }
    if (verdict === CertVerdict.EXPIRING) {
      return `${label}将在 ${daysLeft} 天后过期，请及时联系管理员更新。`;
    }
    return `${label}状态正常。`;
  }
}
